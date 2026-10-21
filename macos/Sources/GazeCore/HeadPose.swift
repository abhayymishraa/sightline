import Foundation
import CoreGraphics

/// One camera reading. Angles are degrees; face numbers are fractions of the camera frame.
public struct HeadPose: Codable, Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var pupilX: Double?      // pupil offset inside the eye opening, in eye widths
    public var pupilY: Double?
    public var faceSize: Double     // face box height; a stand-in for distance to the camera
    public var faceMidX: Double     // face centre, 0...1
    public var faceMidY: Double

    public init(yaw: Double, pitch: Double, pupilX: Double? = nil, pupilY: Double? = nil,
                faceSize: Double, faceMidX: Double = 0.5, faceMidY: Double = 0.5) {
        self.yaw = yaw; self.pitch = pitch; self.pupilX = pupilX; self.pupilY = pupilY
        self.faceSize = faceSize; self.faceMidX = faceMidX; self.faceMidY = faceMidY
    }

    /// The angles as they would read with the face at `base` size. Moving closer to the camera
    /// makes the same screen look like a smaller head turn; this undoes that.
    public func scaled(toFaceSize base: Double) -> HeadPose {
        let k = base / max(faceSize, 0.01)
        var p = self
        p.yaw = atan(k * tan(yaw * .pi / 180)) * 180 / .pi
        p.pitch = atan(k * tan(pitch * .pi / 180)) * 180 / .pi
        return p
    }

    /// Inputs for the gaze regression: head direction, a squared yaw term (screen x is not linear in yaw),
    /// where the face sits in the frame, and optionally the pupil offsets.
    public func features(baseFaceSize base: Double, withPupils: Bool) -> [Double]? {
        let k = base / max(faceSize, 0.01)
        let ty = k * tan(yaw * .pi / 180), tp = tan(pitch * .pi / 180)
        var f = [5 * ty, 5 * k * tp, 5 * ty * abs(ty), 5 * k * (faceMidX - 0.5), 5 * k * (faceMidY - 0.5)]
        if withPupils {
            guard let pupilX, let pupilY else { return nil }
            f += [20 * k * pupilX, 20 * k * pupilY]
        }
        return f
    }

    public var angle: HeadAngle { HeadAngle(yaw: yaw, pitch: pitch) }
}

/// A head direction, in degrees.
public struct HeadAngle: Codable, Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public init(yaw: Double, pitch: Double) { self.yaw = yaw; self.pitch = pitch }

    public func distance(to o: HeadAngle) -> Double { hypot(yaw - o.yaw, pitch - o.pitch) }
    static func - (a: HeadAngle, b: HeadAngle) -> HeadAngle { HeadAngle(yaw: a.yaw - b.yaw, pitch: a.pitch - b.pitch) }
    static func + (a: HeadAngle, b: HeadAngle) -> HeadAngle { HeadAngle(yaw: a.yaw + b.yaw, pitch: a.pitch + b.pitch) }
    func dot(_ o: HeadAngle) -> Double { yaw * o.yaw + pitch * o.pitch }
    var lengthSquared: Double { dot(self) }
}

/// A pose recorded while the user looked at a known spot (x, y) of a screen; unit square, y down.
public struct LookSample: Codable, Equatable, Sendable {
    public var pose: HeadPose
    public var x: Double
    public var y: Double
    public var eyesOnlyPhase: Bool
    public init(pose: HeadPose, x: Double, y: Double, eyesOnlyPhase: Bool = false) {
        self.pose = pose; self.x = x; self.y = y; self.eyesOnlyPhase = eyesOnlyPhase
    }
    var spot: CGPoint { CGPoint(x: x, y: y) }
    var spotKey: String { "\(x),\(y)" }
}

/// Ridge regression from features to a point. Inputs are centred; the intercept is not penalised.
public struct GazeRegressor: Codable, Equatable, Sendable {
    var centre: [Double]
    var weightsX: [Double]
    var weightsY: [Double]

    public static let ridge = 0.02

    public static func train(inputs: [[Double]], outputs: [CGPoint], ridge: Double = ridge) -> GazeRegressor? {
        let n = inputs.count
        guard n >= 8, n == outputs.count else { return nil }
        let d = inputs[0].count
        var centre = [Double](repeating: 0, count: d)
        for row in inputs { for j in 0..<d { centre[j] += row[j] / Double(n) } }
        var a = [[Double]](repeating: [Double](repeating: 0, count: d + 1), count: d + 1)
        var bx = [Double](repeating: 0, count: d + 1), by = bx
        for (row, out) in zip(inputs, outputs) {
            let r = [1.0] + zip(row, centre).map(-)
            for i in 0...d {
                for j in 0...d { a[i][j] += r[i] * r[j] }
                bx[i] += r[i] * out.x
                by[i] += r[i] * out.y
            }
        }
        for j in stride(from: 1, through: d, by: 1) { a[j][j] += ridge * Double(n) }
        guard let wx = gaussianSolve(a, bx), let wy = gaussianSolve(a, by) else { return nil }
        return GazeRegressor(centre: centre, weightsX: wx, weightsY: wy)
    }

    public func map(_ f: [Double]) -> CGPoint {
        let r = [1.0] + zip(f, centre).map(-)
        return CGPoint(x: zip(r, weightsX).map(*).reduce(0, +), y: zip(r, weightsY).map(*).reduce(0, +))
    }

    /// Gaussian elimination with partial pivoting; nil for a singular system.
    static func gaussianSolve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var a = matrix, b = rhs
        let n = b.count
        for col in 0..<n {
            let pivot = (col..<n).max { abs(a[$0][col]) < abs(a[$1][col]) }!
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot); b.swapAt(col, pivot)
            for row in col + 1..<n {
                let f = a[row][col] / a[col][col]
                for k in col..<n { a[row][k] -= f * a[col][k] }
                b[row] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var s = b[row]
            for k in row + 1..<n { s -= a[row][k] * x[k] }
            x[row] = s / a[row][row]
        }
        return x
    }
}

/// The upper middle element; 0.5 for an empty list.
func middleValue(_ values: [Double]) -> Double {
    values.isEmpty ? 0.5 : values.sorted()[values.count / 2]
}
