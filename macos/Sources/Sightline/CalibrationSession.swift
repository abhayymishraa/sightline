import SwiftUI
import GazeCore

/// Drives the session exercise: one full-screen overlay per display, a dot to follow,
/// then a few dots for the eyes only. Produces one `ScreenProfile` per display.
@MainActor
final class CalibrationSession {
    final class Model: ObservableObject {
        enum Phase: Equatable { case ready, running, failed }
        @Published var phase = Phase.ready
        @Published var title = ""
        @Published var subtitle = ""
        @Published var spot = CGPoint(x: 0.5, y: 0.5)
        @Published var spotIndex = 0
        @Published var progress = 0.0         // whole screen, 0...1
        @Published var spotProgress = 0.0      // current dot, 0...1
        @Published var screenLabel = ""
    }

    private struct Sample { var pose: HeadPose; var target: CGPoint }

    private static let eyeSpots = [CGPoint(x: 0.15, y: 0.5), CGPoint(x: 0.85, y: 0.5), CGPoint(x: 0.5, y: 0.15), CGPoint(x: 0.5, y: 0.85)]

    private let displays: [Display]
    private let allDisplays: [Display]
    private let onFinish: ([String: ScreenProfile]?) -> Void
    private let model = Model()
    private var window: CalibrationWindow?
    private var screenIndex = 0
    private var spots: [CGPoint] = []
    private var index = 0
    private var eyesOnly = false
    private var targetStart = Date()
    private var sampleCount = 0
    private var noFaceFrames = 0
    private var smallFaceFrames = 0
    private var samples: [Sample] = []
    private var eyeSamples: [Sample] = []
    private var results: [String: ScreenProfile] = [:]

    /// - Parameters:
    ///   - displays: the displays to calibrate.
    ///   - allDisplays: every connected display, to place dots toward neighbours.
    init(displays: [Display], allDisplays: [Display], onFinish: @escaping ([String: ScreenProfile]?) -> Void) {
        self.displays = displays
        self.allDisplays = allDisplays
        self.onFinish = onFinish
    }

    var isActive: Bool { window != nil }

    func start() { presentScreen() }

    // MARK: Screens

    private func presentScreen() {
        let display = displays[screenIndex]
        spots = Self.spots(for: display, among: allDisplays)
        index = 0
        eyesOnly = false
        samples = []
        eyeSamples = []
        model.phase = .ready
        model.spot = CGPoint(x: 0.5, y: 0.5)
        model.progress = 0
        model.spotProgress = 0
        model.screenLabel = displays.count > 1 ? "Screen \(screenIndex + 1) of \(displays.count): \(display.name)" : display.name
        model.title = "Follow the dot as you naturally would"
        model.subtitle = "\(spots.count + Self.eyeSpots.count) spots on this screen, about 20 seconds."

        window?.orderOut(nil)
        let frame = display.screen?.frame ?? NSScreen.main!.frame
        let w = CalibrationWindow(contentRect: frame)
        w.onKey = { [weak self] code in self?.keyPressed(code) }
        w.contentView = NSHostingView(rootView: CalibrationCanvas(model: model))
        w.setFrame(frame, display: true)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    private func keyPressed(_ code: UInt16) {
        switch code {
        case 49, 36:  // Space, Return
            if model.phase != .running { showSpot(0) }
        case 53:      // Esc
            close()
            onFinish(nil)
        default: break
        }
    }

    private func showSpot(_ i: Int) {
        index = i
        sampleCount = 0
        noFaceFrames = 0
        smallFaceFrames = 0
        targetStart = Date()
        model.phase = .running
        model.spot = eyesOnly ? Self.eyeSpots[i] : spots[i]
        model.spotIndex += 1
        if eyesOnly {
            model.title = "Now hold your head still"
            model.subtitle = "Track the dot with your eyes alone. \(i + 1) of \(Self.eyeSpots.count)"
        } else {
            model.title = "Keep watching the dot"
            model.subtitle = "Spot \(i + 1) of \(spots.count)"
        }
    }

    /// Feed every camera reading here while calibrating.
    func add(_ reading: FaceTracker.Frame) {
        guard model.phase == .running else { return }
        let t = Date().timeIntervalSince(targetStart)
        let duration = eyesOnly ? 2.0 : 1.5
        let total = Double(spots.count + Self.eyeSpots.count)
        model.spotProgress = min(t / duration, 1)
        model.progress = (Double(index + (eyesOnly ? spots.count : 0)) + model.spotProgress) / total

        // Sample once the eyes have settled on the dot.
        if t >= (eyesOnly ? 1.0 : 0.6) {
            switch reading {
            case .face(let pose):
                let s = Sample(pose: pose, target: model.spot)
                if eyesOnly { eyeSamples.append(s) } else { samples.append(s) }
                sampleCount += 1
            case .missing(let small):
                if small { smallFaceFrames += 1 } else { noFaceFrames += 1 }
            }
        }
        guard t >= duration else { return }

        if sampleCount <= 4 {
            showProblem(smallFaceFrames > noFaceFrames
                 ? ("You are too far from the camera", "Move closer, or choose a nearer camera in Preferences. Press Space to retry this screen.")
                 : ("No face in view", "Check the light, that nothing covers the camera, and that Preferences uses the camera in front of you. Press Space to retry this screen."))
            return
        }
        let next = index + 1
        if eyesOnly {
            next < Self.eyeSpots.count ? showSpot(next) : completeScreen()
        } else if next < spots.count {
            showSpot(next)
        } else {
            eyesOnly = true
            showSpot(0)
        }
    }

    private func showProblem(_ message: (String, String)) {
        model.phase = .failed
        model.title = message.0
        model.subtitle = message.1
        model.spot = CGPoint(x: 0.5, y: 0.5)
        samples = []
        eyeSamples = []
        eyesOnly = false
    }

    private func completeScreen() {
        let display = displays[screenIndex]
        var kept: [LookSample] = []
        var dots: [HeadAngle] = []
        for t in spots {
            let s = ScreenProfile.trimmed(samples.filter { $0.target == t }, yaw: \.pose.yaw, pitch: \.pose.pitch)
            guard !s.isEmpty else { continue }
            kept += s.map { LookSample(pose: $0.pose, x: t.x, y: t.y) }
            dots.append(HeadAngle(yaw: Self.median(s.map(\.pose.yaw)), pitch: Self.median(s.map(\.pose.pitch))))
        }
        for t in Self.eyeSpots {
            let s = ScreenProfile.trimmed(eyeSamples.filter { $0.target == t }, yaw: \.pose.yaw, pitch: \.pose.pitch)
            kept += s.map { LookSample(pose: $0.pose, x: t.x, y: t.y, eyesOnlyPhase: true) }
        }
        results[display.id] = ScreenProfile(anchors: dots, samples: kept, frame: display.frame)
        screenIndex += 1
        if screenIndex < displays.count { presentScreen(); return }

        // Two screens whose dots overlap cannot be told apart.
        let saved = Preferences.shared.profiles.filter { id, _ in allDisplays.contains { $0.id == id } && results[id] == nil }
        let centers = saved.merging(results) { $1 }.values.map { Self.centroid($0.anchors) }
        if centers.count >= 2 && Self.minSeparation(centers) < 4 {
            screenIndex = 0
            results = [:]
            presentScreen()
            showProblem(("The camera could not tell these screens apart", "Turn your head, not only your eyes, toward each screen. Press Space to start over."))
            return
        }
        close()
        onFinish(results)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: Geometry

    /// Dots go where precision matters: along the edges shared with neighbouring screens, plus the centre.
    /// A screen with no neighbours gets four inner corners instead.
    static func spots(for d: Display, among all: [Display]) -> [CGPoint] {
        let f = d.frame
        let top = max(0.04, (d.screen?.safeAreaInsets.top ?? 0) / f.height + 0.03)
        func spots(_ lo: Double, _ hi: Double) -> [Double] {
            (hi - lo < 0.3 ? [0.5] : [0.25, 0.5, 0.75]).map { min(max(lo + (hi - lo) * $0, 0.04), 0.96) }
        }
        var points = [CGPoint(x: 0.5, y: 0.5)]
        for n in all where n.id != d.id {
            let g = n.frame
            let yLo = (max(f.minY, g.minY) - f.minY) / f.height, yHi = (min(f.maxY, g.maxY) - f.minY) / f.height
            let xLo = (max(f.minX, g.minX) - f.minX) / f.width, xHi = (min(f.maxX, g.maxX) - f.minX) / f.width
            if abs(g.minX - f.maxX) <= 2, yHi > yLo { points += spots(yLo, yHi).map { CGPoint(x: 0.97, y: max($0, top)) } }
            if abs(g.maxX - f.minX) <= 2, yHi > yLo { points += spots(yLo, yHi).map { CGPoint(x: 0.03, y: max($0, top)) } }
            if abs(g.minY - f.maxY) <= 2, xHi > xLo { points += spots(xLo, xHi).map { CGPoint(x: $0, y: 0.96) } }
            if abs(g.maxY - f.minY) <= 2, xHi > xLo { points += spots(xLo, xHi).map { CGPoint(x: $0, y: top) } }
        }
        if points.count == 1 {
            points += [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.8, y: 0.8)]
        }
        var unique: [CGPoint] = []
        for p in points where !unique.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 0.1 }) { unique.append(p) }
        return unique
    }

    private static func median(_ v: [Double]) -> Double {
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private static func centroid(_ dots: [HeadAngle]) -> HeadAngle {
        let n = Double(max(dots.count, 1))
        return HeadAngle(yaw: dots.map(\.yaw).reduce(0, +) / n, pitch: dots.map(\.pitch).reduce(0, +) / n)
    }

    private static func minSeparation(_ points: [HeadAngle]) -> Double {
        var best = Double.infinity
        for i in points.indices { for j in points.indices where j > i {
            best = min(best, hypot(points[i].yaw - points[j].yaw, points[i].pitch - points[j].pitch))
        } }
        return best
    }
}

/// Borderless full-screen window that can take key presses.
final class CalibrationWindow: NSWindow {
    var onKey: ((UInt16) -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = NSColor(srgbRed: 0.965, green: 0.969, blue: 0.973, alpha: 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event.keyCode) }
}

/// The overlay is always light: a bright screen lights the face, which helps the camera.
struct CalibrationCanvas: View {
    @ObservedObject var model: CalibrationSession.Model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let textColor = Color(red: 0.086, green: 0.098, blue: 0.11)
    private let textMuted = Color(red: 0.35, green: 0.38, blue: 0.41)
    private let brand = Color(red: 0.118, green: 0.616, blue: 0.945)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.965, green: 0.969, blue: 0.973)

                if model.phase == .running {
                    dot
                        .position(x: model.spot.x * geo.size.width, y: model.spot.y * geo.size.height)
                        .animation(reduceMotion ? nil : .timingCurve(0.77, 0, 0.175, 1, duration: 0.45), value: model.spotIndex)
                        .transition(.opacity)
                }

                VStack(spacing: 10) {
                    if model.phase != .running {
                        Image(systemName: model.phase == .failed ? "exclamationmark.triangle.fill" : "display.2")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(model.phase == .failed ? Color(red: 0.706, green: 0.137, blue: 0.094) : brand)
                            .padding(.bottom, 6)
                        Text(model.screenLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(textMuted)
                    }
                    Text(model.title)
                        .font(.system(size: model.phase == .running ? 17 : 24, weight: .semibold))
                        .foregroundStyle(textColor)
                    Text(model.subtitle)
                        .font(.system(size: model.phase == .running ? 13 : 15))
                        .foregroundStyle(textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                    if model.phase != .running {
                        HStack(spacing: 6) {
                            KeyHint("Space"); Text("start").foregroundStyle(textMuted)
                            KeyHint("Esc").padding(.leading, 10); Text("cancel").foregroundStyle(textMuted)
                        }
                        .font(.system(size: 12))
                        .padding(.top, 14)
                    }
                }
                .padding(.horizontal, 40)
                .position(x: geo.size.width / 2, y: geo.size.height / 2 + (model.phase == .running ? 110 : 0))
                .animation(.easeOut(duration: 0.2), value: model.phase)

                // Thin progress bar along the bottom edge.
                VStack {
                    Spacer()
                    Rectangle().fill(brand)
                        .frame(width: geo.size.width * model.progress, height: 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
    }

    private var dot: some View {
        ZStack {
            Circle().stroke(brand.opacity(0.15), lineWidth: 3).frame(width: 40, height: 40)
            Circle().trim(from: 0, to: model.spotProgress)
                .stroke(brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 40, height: 40)
            Circle().fill(brand).frame(width: 16, height: 16)
            Circle().fill(.white).frame(width: 5, height: 5)
        }
    }
}

private struct KeyHint: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(red: 0.086, green: 0.098, blue: 0.11))
            .padding(.horizontal, 7).frame(height: 22)
            .background(.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.black.opacity(0.1)))
    }
}
