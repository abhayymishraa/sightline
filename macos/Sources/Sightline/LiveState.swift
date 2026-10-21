import SwiftUI
import AVFoundation
import GazeCore

/// Live state the windows observe. Written only by AppDelegate on the main thread.
@MainActor
final class LiveState: ObservableObject {
    static let shared = LiveState()

    @Published var displays: [Display] = []
    @Published var lookingAtID: String?
    @Published var gaze: CGPoint?          // global points
    @Published var pose: HeadPose?
    @Published var cameraProblem: String?
    @Published var cameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published var accessibilityAllowed = AXIsProcessTrusted()
    @Published var unreliableIDs: Set<String> = []
    @Published var screensMoved = false
    @Published var isLocked = false
    @Published var cameras: [AVCaptureDevice] = FaceTracker.cameras()

    var seesFace: Bool { pose != nil }

    func unprofiled(_ prefs: Preferences) -> [Display] {
        displays.filter { prefs.profiles[$0.id] == nil }
    }

    enum Mode: Equatable {
        case paused, locked, noDisplay, needsCamera, needsAccessibility, needsCalibration, oneDisplay
        case lookingForFace, tracking(String)
    }

    func mode(_ s: Preferences) -> Mode {
        if isLocked { return .locked }
        if !cameraAllowed { return .needsCamera }
        if !accessibilityAllowed { return .needsAccessibility }
        if !s.active { return .paused }
        if displays.isEmpty { return .noDisplay }
        if displays.count == 1 && !s.followWithinScreen { return .oneDisplay }
        if unprofiled(s).count == displays.count { return .needsCalibration }
        guard pose != nil else { return .lookingForFace }
        return .tracking(displays.first { $0.id == lookingAtID }?.name ?? "")
    }

    func summary(_ s: Preferences) -> String {
        switch mode(s) {
        case .paused: "Paused"
        case .locked: "Off while the screen is locked"
        case .noDisplay: "Waiting for a screen"
        case .needsCamera: "Camera not allowed"
        case .needsAccessibility: "Accessibility not allowed"
        case .needsCalibration: "Screens not set up"
        case .oneDisplay: "One screen. Turn on pane focus in Preferences"
        case .lookingForFace: "Watching, no face in view"
        case .tracking(let name): name.isEmpty ? "Watching" : "Watching, you face \(name)"
        }
    }
}

/// A scaled map of the connected displays. Highlights the screen you face and shows the estimated gaze point.
struct ScreenMap: View {
    @ObservedObject var state = LiveState.shared
    @ObservedObject var prefs = Preferences.shared
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let union = state.displays.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = union.isNull ? 1 : min(geo.size.width / union.width, geo.size.height / union.height) * 0.92
            let origin = CGPoint(x: (geo.size.width - union.width * scale) / 2, y: (geo.size.height - union.height * scale) / 2)
            ZStack(alignment: .topLeading) {
                if state.displays.isEmpty {
                    Label("No screens found", systemImage: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                ForEach(state.displays) { d in
                    let facing = d.id == state.lookingAtID
                    let calibrated = prefs.profiles[d.id] != nil
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(facing ? Theme.brandTint : Theme.backdrop)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(facing ? Theme.brand : Theme.hairline, lineWidth: facing ? 1.5 : 1))
                        .overlay(
                            VStack(spacing: 2) {
                                Text(d.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                if !calibrated { Text("Not set up").font(.system(size: 9)).foregroundStyle(Theme.caution) }
                            }
                            .foregroundStyle(facing ? Theme.brand : Theme.textMuted)
                            .padding(4)
                        )
                        .frame(width: max(d.frame.width * scale - 4, 0), height: max(d.frame.height * scale - 4, 0))
                        .offset(x: origin.x + (d.frame.minX - union.minX) * scale + 2, y: origin.y + (d.frame.minY - union.minY) * scale + 2)
                        .animation(Theme.snap, value: facing)
                }
                if let g = state.gaze, !union.isNull {
                    Circle().fill(Theme.brand).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                        .offset(x: origin.x + (g.x - union.minX) * scale - 4, y: origin.y + (g.y - union.minY) * scale - 4)
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel(Text(state.summary(prefs)))
    }
}
