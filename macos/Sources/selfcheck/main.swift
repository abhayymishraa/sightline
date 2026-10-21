// Runs the gaze math against synthetic data. `swift run selfcheck` exits non-zero on failure.
import Foundation
import CoreGraphics
import GazeCore

func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { exit(1) }
}

// 1€ filter: the first value passes, a step is smoothed, and the output converges.
var f = OneEuroFilter(minCutoff: 0.25, beta: 0.03)
check(f.filter(10, at: 0) == 10, "filter passes first value")
let firstStep = f.filter(20, at: 1.0 / 15)
check(firstStep > 10 && firstStep < 20, "filter smooths a step")
var last = firstStep
for i in 2...300 { last = f.filter(20, at: Double(i) / 15) }
check(abs(last - 20) < 0.01, "filter converges")

// Ridge regression recovers a linear map from head angles to screen position.
var inputs: [[Double]] = [], outputs: [CGPoint] = []
for x in stride(from: 0.1, through: 0.9, by: 0.2) {
    for y in stride(from: 0.1, through: 0.9, by: 0.4) {
        let pose = HeadPose(yaw: 30 * (x - 0.5), pitch: 15 * (y - 0.5), faceSize: 0.4)
        inputs.append(pose.features(baseFaceSize: 0.4, withPupils: false)!)
        outputs.append(CGPoint(x: x, y: y))
    }
}
let model = GazeRegressor.train(inputs: inputs, outputs: outputs)
check(model != nil, "regressor trains")
let probe = HeadPose(yaw: 30 * (0.6 - 0.5), pitch: 15 * (0.3 - 0.5), faceSize: 0.4)
let guess = model!.map(probe.features(baseFaceSize: 0.4, withPupils: false)!)
check(abs(guess.x - 0.6) < 0.05 && abs(guess.y - 0.3) < 0.05, "regressor maps a held-out point (\(guess))")

// Distance scaling: the same angle seen from farther away (smaller face) maps to a larger angle.
let far = HeadPose(yaw: 10, pitch: 0, faceSize: 0.2).scaled(toFaceSize: 0.4)
check(far.yaw > 10 && far.yaw < 20, "far face scales yaw up (\(far.yaw))")

// Screen picker: two screens side by side, left anchors near yaw +20, right anchors near yaw -20.
let anchors: [String: [HeadAngle]] = [
    "L": [HeadAngle(yaw: 25, pitch: 0), HeadAngle(yaw: 15, pitch: 0)],
    "R": [HeadAngle(yaw: -15, pitch: 0), HeadAngle(yaw: -25, pitch: 0)],
]
let picker = ScreenPicker()
func step(_ yaw: Double, _ t: Double) -> String? {
    picker.step(head: HeadAngle(yaw: yaw, pitch: 0), anchors: anchors, delay: 0.2, boundary: 0.5, now: t)
}
_ = step(20, 0)
check(picker.screen == "L", "picker starts on the nearest screen")
check(step(5, 0.1) == nil && step(5, 0.5) == nil, "no move before the boundary")
check(step(-10, 1.0) == nil, "contender must hold first")
check(step(-10, 1.3) == "R", "moves after the delay")
check(step(-2, 2.0) == nil && step(-2, 2.5) == nil, "turning back a little does not move")
_ = step(12, 3.0)
check(step(12, 3.3) == "L", "moves back once well back")
check(step(80, 4.0) == nil && picker.screen == "L", "looking far away changes nothing")

var misses = MissCounter()
var flagged = false
for _ in 0..<8 { flagged = misses.note(screen: "L", miss: true) || flagged }
check(flagged && misses.isUnreliable("L"), "miss counter flags repeated misses")

// Screen profile: head and pupil samples; pupils carry real signal, so the pupil model wins.
var samples: [LookSample] = []
var rng = SystemRandomNumberGenerator()
for (x, y) in [(0.5, 0.5), (0.97, 0.25), (0.97, 0.5), (0.97, 0.75)] {
    for _ in 0..<12 {
        let n = Double.random(in: -0.3...0.3, using: &rng)
        samples.append(LookSample(pose: HeadPose(yaw: 20 * (x - 0.5) + n, pitch: 10 * (y - 0.5) + n,
                                                 pupilX: 0.3 * (x - 0.5), pupilY: 0.3 * (y - 0.5), faceSize: 0.35), x: x, y: y))
    }
}
for (x, y) in [(0.15, 0.5), (0.85, 0.5), (0.5, 0.15), (0.5, 0.85)] {
    for _ in 0..<12 {
        samples.append(LookSample(pose: HeadPose(yaw: 0, pitch: 0, pupilX: 0.3 * (x - 0.5), pupilY: 0.3 * (y - 0.5), faceSize: 0.35),
                                  x: x, y: y, eyesOnlyPhase: true))
    }
}
var profile = ScreenProfile(anchors: [HeadAngle(yaw: 0, pitch: 0), HeadAngle(yaw: 9.4, pitch: 0)], samples: samples)
check(profile.pupilsUseful == true, "pupils beat head-only when they carry signal")
let seen = profile.locate(HeadPose(yaw: 0, pitch: 0, pupilX: 0.3 * (0.2 - 0.5), pupilY: 0, faceSize: 0.35))!
check(abs(seen.x - 0.2) < 0.1, "pupil-only gaze lands left on the screen (\(seen))")
let data = try! JSONEncoder().encode(profile)
check((try? JSONDecoder().decode(ScreenProfile.self, from: data)) == profile, "profile round-trips through JSON")
for _ in 0..<10 {
    profile.absorbClick(pose: HeadPose(yaw: 3, pitch: 0, pupilX: 0, pupilY: 0, faceSize: 0.35, faceMidX: 0.6), at: CGPoint(x: 0.5, y: 0.5))
}
check(profile.seatShift(for: HeadPose(yaw: 0, pitch: 0, faceSize: 0.35, faceMidX: 0.6)).yaw > 1.5, "clicks teach a seat shift")
print("all checks passed")
