import Foundation

/// The 1€ filter (Casiez et al., CHI 2012): low lag when the signal moves fast, heavy smoothing when it is still.
public struct OneEuroFilter {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double
    private var value: Double?
    private var derivative = 0.0
    private var lastTime = 0.0

    public init(minCutoff: Double, beta: Double, dCutoff: Double = 1) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public mutating func reset() { value = nil; derivative = 0 }

    public mutating func filter(_ x: Double, at t: Double) -> Double {
        defer { lastTime = t }
        guard let previous = value, t > lastTime else { value = x; return x }
        let dt = t - lastTime
        derivative += Self.alpha(dCutoff, dt) * ((x - previous) / dt - derivative)
        let cutoff = minCutoff + beta * abs(derivative)
        let next = previous + Self.alpha(cutoff, dt) * (x - previous)
        value = next
        return next
    }

    private static func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        1 / (1 + 1 / (2 * .pi * cutoff * dt))
    }
}
