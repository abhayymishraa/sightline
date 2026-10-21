import AVFoundation
import Vision
import GazeCore

/// Camera → Vision → filtered `HeadPose`, 15 times a second.
/// Capture and Vision run on a private queue; results arrive on the main queue.
final class FaceTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Frame { case face(HeadPose), missing(tooSmall: Bool) }

    var onFrame: ((Frame) -> Void)?
    /// A camera problem, or nil once frames flow again.
    var onProblem: ((String?) -> Void)?
    private(set) var activeCameraID: String?

    private let queue = DispatchQueue(label: "sightline.capture", qos: .userInteractive)
    private let session = AVCaptureSession()
    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        r.revision = VNDetectFaceRectanglesRequestRevision3   // revision 3 reports yaw and pitch
        return r
    }()
    private let landmarksRequest = VNDetectFaceLandmarksRequest()

    private let fps = 15.0
    private let smallestFace = 0.08
    private let pupilHoldSeconds = 1.2                // keep the last eye reading through a short dropout
    private var nextFrameDue = 0.0
    private var awaitingFirstFrame = false
    private var generation = 0

    private var yawF = OneEuroFilter(minCutoff: 0.25, beta: 0.03)
    private var pitchF = OneEuroFilter(minCutoff: 0.25, beta: 0.03)
    private var eyeXF = OneEuroFilter(minCutoff: 1, beta: 0.8)
    private var eyeYF = OneEuroFilter(minCutoff: 1, beta: 0.8)
    private var faceHF = OneEuroFilter(minCutoff: 0.5, beta: 1)
    private var faceXF = OneEuroFilter(minCutoff: 0.5, beta: 1)
    private var faceYF = OneEuroFilter(minCutoff: 0.5, beta: 1)
    private var lastEyes: (x: Double, y: Double, time: Double)?
    private var recentEyes: [(x: Double, y: Double)] = []
    private var recentOpenness: [Double] = []

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external],
                                         mediaType: .video, position: .unspecified).devices.filter(\.isConnected)
    }

    /// An explicit choice wins; then a real external camera; then the built-in one.
    static func camera(for id: String?) -> AVCaptureDevice? {
        let cams = cameras()
        if let id, let d = cams.first(where: { $0.uniqueID == id }) { return d }
        return cams.first { $0.deviceType == .external && !"\($0.localizedName) \($0.modelID)".localizedCaseInsensitiveContains("virtual") }
            ?? cams.first { $0.deviceType == .builtInWideAngleCamera }
            ?? cams.first
    }

    func start(cameraChoice: String?) {
        queue.async { [self] in setUp(cameraChoice) }
    }

    func stop() {
        queue.async { [self] in
            generation += 1
            if session.isRunning { session.stopRunning() }
        }
    }

    private func setUp(_ cameraChoice: String?) {
        if session.isRunning { session.stopRunning() }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720
            : session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .low
        guard let device = Self.camera(for: cameraChoice),
              let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
            session.commitConfiguration()
            tell("No camera available")
            return
        }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()
        limitFrameRate(device)
        resetFilters()
        activeCameraID = device.uniqueID
        generation += 1
        awaitingFirstFrame = true
        let started = generation
        queue.asyncAfter(deadline: .now() + 10) { [self] in
            if generation == started && awaitingFirstFrame { tell("The camera sends no frames") }
        }
    }

    /// Fewer frames from the camera means less USB bandwidth and heat; we only process 15 per second anyway.
    private func limitFrameRate(_ device: AVCaptureDevice) {
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= fps && $0.maxFrameRate >= fps }),
              (try? device.lockForConfiguration()) != nil else { return }
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        device.unlockForConfiguration()
    }

    private func tell(_ error: String?) {
        DispatchQueue.main.async { self.onProblem?(error) }
    }

    private func resetFilters() {
        yawF.reset(); pitchF.reset(); faceHF.reset(); faceXF.reset(); faceYF.reset()
        resetEyes()
    }

    private func resetEyes() {
        eyeXF.reset(); eyeYF.reset(); lastEyes = nil; recentEyes = []
    }

    // MARK: Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if awaitingFirstFrame { awaitingFirstFrame = false; tell(nil) }
        let now = CACurrentMediaTime()
        guard nextFrameDue - 0.012 <= now, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        nextFrameDue = max(nextFrameDue, now - 1 / fps) + 1 / fps

        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up)
        try? handler.perform([faceRequest])
        let all = faceRequest.results ?? []
        // The largest face is the person at the desk.
        guard let face = all.filter({ $0.boundingBox.width >= smallestFace }).max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let yaw = face.yaw?.doubleValue, let pitch = face.pitch?.doubleValue else {
            resetFilters()
            deliver(.missing(tooSmall: !all.isEmpty))
            return
        }

        landmarksRequest.inputFaceObservations = [face]
        try? handler.perform([landmarksRequest])
        let eyes = (landmarksRequest.results?.first?.landmarks).flatMap(Self.pupilOffset).flatMap(steadyPupils)

        let box = face.boundingBox
        var pose = HeadPose(
            yaw: yawF.filter(yaw * 180 / .pi, at: now),
            pitch: pitchF.filter(pitch * 180 / .pi, at: now),
            faceSize: faceHF.filter(box.height, at: now),
            faceMidX: faceXF.filter(box.midX, at: now),
            faceMidY: faceYF.filter(box.midY, at: now)
        )
        if let eyes {
            pose.pupilX = eyeXF.filter(eyes.x, at: now)
            pose.pupilY = eyeYF.filter(eyes.y, at: now)
            lastEyes = (pose.pupilX!, pose.pupilY!, now)
        } else if let last = lastEyes, now - last.time < pupilHoldSeconds {
            pose.pupilX = last.x
            pose.pupilY = last.y
        } else {
            resetEyes()
        }
        deliver(.face(pose))
    }

    private func deliver(_ frame: Frame) {
        DispatchQueue.main.async { self.onFrame?(frame) }
    }

    /// Drops blinks (eye much less open than usual) and takes a 3-frame median against pupil jitter.
    private func steadyPupils(_ r: (x: Double, y: Double, open: Double)) -> (x: Double, y: Double)? {
        let usual = median(recentOpenness)
        recentOpenness.append(r.open)
        if recentOpenness.count > 150 { recentOpenness.removeFirst() }
        if recentOpenness.count >= 15 && r.open < usual * 0.6 { return nil }
        recentEyes.append((r.x, r.y))
        if recentEyes.count > 3 { recentEyes.removeFirst() }
        return (median(recentEyes.map(\.x)), median(recentEyes.map(\.y)))
    }

    /// Pupil position inside each eye opening, in eye widths, weighted by eye size (the nearer eye is sharper).
    private static func pupilOffset(_ lm: VNFaceLandmarks2D) -> (x: Double, y: Double, open: Double)? {
        var x = 0.0, y = 0.0, open = 0.0, total = 0.0
        for (pupil, eye) in [(lm.rightPupil, lm.rightEye), (lm.leftPupil, lm.leftEye)] {
            guard let pupil, let eye, eye.pointCount >= 4, let p = pupil.normalizedPoints.first else { continue }
            let pts = eye.normalizedPoints
            let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
            let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
            let w = Double(maxX - minX)
            guard w > 0.01 else { continue }
            let weight = w * w
            x += weight * Double(p.x - (minX + maxX) / 2) / w
            y += weight * Double(p.y - (minY + maxY) / 2) / w
            open += weight * Double(maxY - minY) / w
            total += weight
        }
        return total > 0 ? (x / total, y / total, open / total) : nil
    }

    private func median(_ v: [Double]) -> Double { v.isEmpty ? 0 : v.sorted()[v.count / 2] }
}
