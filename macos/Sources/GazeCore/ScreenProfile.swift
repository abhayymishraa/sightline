import Foundation
import CoreGraphics

/// What one screen looks like from the user's seat: anchor head angles, the samples they came from,
/// and two regressions (head only, and head plus pupils).
public struct ScreenProfile: Codable, Equatable, Sendable {
    public var baseFaceSize: Double
    public var middle: HeadAngle
    public var anchors: [HeadAngle]
    var samples: [LookSample]
    var clicks: [LookSample] = []
    var seatShifts: [SeatShift] = []
    public var frame: CGRect?            // screen frame when profiled, to notice rearranged screens
    var withPupils: GazeRegressor?
    var headOnly: GazeRegressor?
    public var pupilsUseful: Bool?       // true when pupils lower the held-out error

    public init(anchors: [HeadAngle], samples: [LookSample], frame: CGRect? = nil) {
        baseFaceSize = samples.isEmpty ? 0.3 : middleValue(samples.map(\.pose.faceSize))
        self.anchors = anchors
        middle = anchors.first ?? HeadAngle(yaw: 0, pitch: 0)
        self.samples = samples
        self.frame = frame
        retrain()
        if let p = crossValidate(withPupils: true), let h = crossValidate(withPupils: false) {
            pupilsUseful = p.error < h.error
        }
    }

    mutating func retrain() {
        let all = samples + clicks
        let pupilRows = all.compactMap { s in s.pose.features(baseFaceSize: baseFaceSize, withPupils: true).map { ($0, s.spot) } }
        withPupils = GazeRegressor.train(inputs: pupilRows.map(\.0), outputs: pupilRows.map(\.1))
        let headRows = all.filter { !$0.eyesOnlyPhase }
        headOnly = GazeRegressor.train(inputs: headRows.map { $0.pose.features(baseFaceSize: baseFaceSize, withPupils: false)! },
                                       outputs: headRows.map(\.spot))
    }

    public var pupilModel: GazeRegressor? { pupilsUseful == false ? nil : withPupils }

    /// Where on this screen (unit square) the user looks, or nil without a trained model.
    public func locate(_ pose: HeadPose) -> CGPoint? {
        var p: CGPoint?
        if pupilsUseful != false, let withPupils, let f = pose.features(baseFaceSize: baseFaceSize, withPupils: true) {
            p = withPupils.map(f)
        } else if let headOnly, let f = pose.features(baseFaceSize: baseFaceSize, withPupils: false) {
            p = headOnly.map(f)
        }
        return p.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
    }

    /// Leave-one-spot-out error and scatter, in fractions of the screen.
    public func crossValidate(withPupils pupils: Bool) -> (error: Double, scatter: Double)? {
        let pool = pupils ? samples : samples.filter { !$0.eyesOnlyPhase }
        let spots = Dictionary(grouping: samples.filter { !$0.eyesOnlyPhase }, by: \.spotKey)
        var errors: [Double] = [], scatter: [Double] = []
        for (key, held) in spots {
            let rows = pool.compactMap { s -> ([Double], CGPoint)? in
                guard s.spotKey != key else { return nil }
                return s.pose.features(baseFaceSize: baseFaceSize, withPupils: pupils).map { ($0, s.spot) }
            }
            guard let model = GazeRegressor.train(inputs: rows.map(\.0), outputs: rows.map(\.1)) else { continue }
            let guesses = held.compactMap { s in s.pose.features(baseFaceSize: baseFaceSize, withPupils: pupils).map(model.map) }
            guard !guesses.isEmpty, let truth = held.first?.spot else { continue }
            errors += guesses.map { Double(hypot($0.x - truth.x, $0.y - truth.y)) }
            let mx = CGFloat(middleValue(guesses.map { Double($0.x) })), my = CGFloat(middleValue(guesses.map { Double($0.y) }))
            scatter += guesses.map { Double(hypot($0.x - mx, $0.y - my)) }
        }
        guard !errors.isEmpty else { return nil }
        return (errors.reduce(0, +) / Double(errors.count), scatter.reduce(0, +) / Double(scatter.count))
    }

    // MARK: Clicks

    /// The user clicked at `spot` on this screen, so they were almost surely looking there.
    /// The seat shift always learns; the click joins the regression only when the current guess was
    /// near, so a click made while looking elsewhere cannot spoil the model.
    public mutating func absorbClick(pose: HeadPose, at spot: CGPoint) {
        let scaled = pose.scaled(toFaceSize: baseFaceSize)
        let expected = expectedAngle(at: spot)
        if abs(scaled.yaw - expected.yaw) < 25, abs(scaled.pitch - expected.pitch) < 20 {
            seatShifts.append(SeatShift(yaw: scaled.yaw - expected.yaw, pitch: scaled.pitch - expected.pitch,
                                        faceMidX: pose.faceMidX, faceMidY: pose.faceMidY))
            if seatShifts.count > 30 { seatShifts.removeFirst(seatShifts.count - 30) }
        }
        guard let guess = locate(pose), hypot(guess.x - spot.x, guess.y - spot.y) < 0.45 else { return }
        clicks.append(LookSample(pose: pose, x: spot.x, y: spot.y))
        if clicks.count > 200 { clicks.removeFirst(clicks.count - 200) }
        retrain()
    }

    /// Anchors moved by the learned seat shift, for the screen picker.
    public func shiftedAnchors(for pose: HeadPose) -> [HeadAngle] {
        let s = seatShift(for: pose)
        return anchors.map { $0 + s }
    }

    /// How far head angles have moved since profiling (a moved chair, leaning to one side),
    /// predicted from where the face sits in the frame. Few clicks keep it near zero.
    public func seatShift(for pose: HeadPose) -> HeadAngle {
        let s = Self.trimmed(seatShifts, yaw: \.yaw, pitch: \.pitch)
        guard s.count >= 3 else { return HeadAngle(yaw: 0, pitch: 0) }
        let x = Self.trend(s.map { ($0.yaw, $0.faceMidX) }, at: pose.faceMidX)
        let y = Self.trend(s.map { ($0.pitch, $0.faceMidY) }, at: pose.faceMidY)
        let confidence = Double(s.count) / Double(s.count + 4)
        return HeadAngle(yaw: confidence * x, pitch: confidence * y)
    }

    /// Mean shift, plus a regularised linear trend against face position once there are enough points.
    private static func trend(_ pairs: [(shift: Double, face: Double)], at face: Double) -> Double {
        let n = Double(pairs.count)
        let meanFace = pairs.map(\.face).reduce(0, +) / n
        let meanShift = pairs.map(\.shift).reduce(0, +) / n
        guard pairs.count >= 8 else { return meanShift }
        let cov = pairs.map { ($0.shift - meanShift) * ($0.face - meanFace) }.reduce(0, +)
        let spread = pairs.map { ($0.face - meanFace) * ($0.face - meanFace) }.reduce(0, +)
        return meanShift + (face - meanFace) * cov / (spread + 0.0005 * n)
    }

    /// Head angle expected when looking at `p`, weighted by inverse squared distance to the profiled spots.
    private func expectedAngle(at p: CGPoint) -> HeadAngle {
        var sw = 0.0, sy = 0.0, sp = 0.0
        for group in Dictionary(grouping: samples.filter { !$0.eyesOnlyPhase }, by: \.spotKey).values {
            guard let t = group.first?.spot else { continue }
            let scaled = group.map { $0.pose.scaled(toFaceSize: baseFaceSize) }
            let w = 1 / ((t.x - p.x) * (t.x - p.x) + (t.y - p.y) * (t.y - p.y) + 0.001)
            sw += w; sy += w * middleValue(scaled.map(\.yaw)); sp += w * middleValue(scaled.map(\.pitch))
        }
        return sw > 0 ? HeadAngle(yaw: sy / sw, pitch: sp / sw) : middle
    }

    /// Drops items more than 3 median absolute deviations (at least 1°) from the median.
    public static func trimmed<T>(_ items: [T], yaw: KeyPath<T, Double>, pitch: KeyPath<T, Double>) -> [T] {
        guard items.count >= 5 else { return items }
        let my = middleValue(items.map { $0[keyPath: yaw] }), mp = middleValue(items.map { $0[keyPath: pitch] })
        let dy = max(3 * middleValue(items.map { abs($0[keyPath: yaw] - my) }), 1)
        let dp = max(3 * middleValue(items.map { abs($0[keyPath: pitch] - mp) }), 1)
        let kept = items.filter { abs($0[keyPath: yaw] - my) <= dy && abs($0[keyPath: pitch] - mp) <= dp }
        return kept.count <= 2 ? items : kept
    }
}

struct SeatShift: Codable, Equatable, Sendable {
    var yaw, pitch, faceMidX, faceMidY: Double
}
