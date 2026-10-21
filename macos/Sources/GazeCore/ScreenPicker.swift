import Foundation

/// Picks the screen the user faces from head yaw/pitch.
///
/// Each screen is a set of anchor angles from calibration. The head angle is projected onto the line
/// between the nearest anchor of the current screen and the nearest anchor of another screen;
/// `boundary` is how far along that line the head must go. Turning back needs a bigger move,
/// and a contender must hold for `delay` seconds before it wins.
public final class ScreenPicker {
    public private(set) var screen: String?
    private var lastScreen: String?
    private var pivot: (from: HeadAngle, to: HeadAngle)?
    private var crossedAt = 0.0
    private var contender: String?
    private var contenderSince = 0.0
    private var contenderSeen = 0.0
    private var lastMoveAt = -Double.infinity

    let backoff = 0.12, verticalBackoff = 0.2
    let eyeNudge = 0.25
    let verticalBoundaryExtra = 0.15, verticalDelayExtra = 0.3
    let minimumHold = 0.4
    let sideTolerance = 5.0, sideToleranceFraction = 0.5

    public init() {}

    public func reset() { screen = nil; lastScreen = nil; pivot = nil; contender = nil }

    /// Treat `id` as the current screen, for example after the user clicked there.
    public func pin(_ id: String) {
        guard id != screen else { return }
        screen = id; lastScreen = nil; pivot = nil; contender = nil
    }

    /// - Parameters:
    ///   - head: distance-scaled head angle.
    ///   - anchors: anchor angles per screen ID.
    ///   - pupils: for a target screen, true if the eyes point there, false if they point at the current one.
    /// - Returns: the screen to move to now, or nil.
    public func step(head p: HeadAngle, anchors: [String: [HeadAngle]], delay: Double, boundary: Double,
                     now: Double, pupils: ((String) -> Bool?)? = nil) -> String? {
        guard anchors.count >= 2, let near = nearestScreen(p, anchors),
              let nearAnchor = nearest(p, in: anchors[near]!) else { contender = nil; return nil }
        // Far from every anchor: looking at the desk, a phone, or away.
        if p.distance(to: nearAnchor) > max(12, 0.8 * closestGap(anchors)) { contender = nil; return nil }

        guard let here = screen, let hereAnchors = anchors[here], let hereAnchor = nearest(p, in: hereAnchors) else {
            screen = near; lastScreen = nil; pivot = nil; contender = nil
            return nil
        }
        let hereMid = mean(hereAnchors)
        let d = p - hereAnchor

        var best: (id: String, score: Double, line: Double, vertical: Bool, anchor: HeadAngle)?
        var contenderAside = false
        for (id, list) in anchors where id != here && !list.isEmpty {
            let there = nearest(p, in: list)!
            let axis = there - hereAnchor
            let length = axis.lengthSquared.squareRoot()
            let aside = length > 1e-9 ? abs(d.yaw * axis.pitch - d.pitch * axis.yaw) / length : d.lengthSquared.squareRoot()
            if aside > max(sideTolerance, sideToleranceFraction * length) {
                if contender == id { contenderAside = true }
                continue
            }
            let t = length > 1e-9 ? d.dot(axis) / (length * length) : 0
            let vote = pupils?(id)
            let nudge = vote == true ? eyeNudge : vote == false ? -eyeNudge : 0
            let vertical = abs(mean(list).yaw - hereMid.yaw) < abs(mean(list).pitch - hereMid.pitch)
            let line = min(boundary + (vertical ? verticalBoundaryExtra : 0), 0.9) - nudge
            var score = t
            var passes = line <= t
            if id == lastScreen, let pv = pivot {
                let axisBack = pv.to - pv.from
                let tBack = axisBack.lengthSquared > 1e-9 ? (p - pv.from).dot(axisBack) / axisBack.lengthSquared : 0
                passes = tBack <= crossedAt - (vertical ? verticalBackoff : backoff) + nudge
                score = max(t, 1 - tBack)
            }
            if passes && score > (best?.score ?? 0) { best = (id, score, line, vertical, there) }
        }

        guard let b = best else {
            if contenderAside && now - contenderSeen <= 0.25 { return nil }
            contender = nil
            return nil
        }
        contenderSeen = now
        if contender != b.id { contender = b.id; contenderSince = now; return nil }
        guard now - contenderSince >= delay + (b.vertical ? verticalDelayExtra : 0),
              now - lastMoveAt >= minimumHold else { return nil }

        let previous = here
        screen = b.id
        lastMoveAt = now
        contender = nil
        if lastScreen == b.id { pivot = nil; lastScreen = nil; return b.id }
        let to = nearest(hereAnchor, in: anchors[b.id]!) ?? b.anchor
        let axis = to - hereAnchor
        pivot = (from: hereAnchor, to: to)
        crossedAt = axis.lengthSquared > 1e-9 ? min(b.line, d.dot(axis) / axis.lengthSquared) : 0
        lastScreen = previous
        return b.id
    }

    private func nearest(_ p: HeadAngle, in list: [HeadAngle]) -> HeadAngle? {
        list.min { p.distance(to: $0) < p.distance(to: $1) }
    }

    private func nearestScreen(_ p: HeadAngle, _ anchors: [String: [HeadAngle]]) -> String? {
        anchors.compactMap { id, list in nearest(p, in: list).map { (id, p.distance(to: $0)) } }.min { $0.1 < $1.1 }?.0
    }

    private func mean(_ list: [HeadAngle]) -> HeadAngle {
        let n = Double(max(list.count, 1))
        return HeadAngle(yaw: list.map(\.yaw).reduce(0, +) / n, pitch: list.map(\.pitch).reduce(0, +) / n)
    }

    /// Smallest anchor-to-anchor distance between two different screens.
    private func closestGap(_ anchors: [String: [HeadAngle]]) -> Double {
        let all = Array(anchors.values)
        var best = Double.infinity
        for i in all.indices {
            for j in all.indices where j > i {
                for a in all[i] { for b in all[j] { best = min(best, a.distance(to: b)) } }
            }
        }
        return best
    }
}

/// Tracks, per screen, how often the gaze estimate disagrees with where the user clicks.
public struct MissCounter {
    private var results: [String: [Bool]] = [:]
    /// Screens whose position changed; they need fewer misses to be flagged.
    public var suspect: Set<String> = []

    public init() {}

    public func isUnreliable(_ screen: String) -> Bool {
        let minimum = suspect.contains(screen) ? 4 : 8
        guard let r = results[screen], r.count >= minimum else { return false }
        return Double(r.filter { $0 }.count) / Double(r.count) >= 0.5
    }

    /// Returns true only when the screen turns unreliable with this result.
    public mutating func note(screen: String, miss: Bool) -> Bool {
        let was = isUnreliable(screen)
        results[screen, default: []].append(miss)
        if results[screen]!.count > 16 { results[screen]!.removeFirst(results[screen]!.count - 16) }
        return !was && isUnreliable(screen)
    }

    public mutating func forget(_ screen: String) { results[screen] = nil }
}
