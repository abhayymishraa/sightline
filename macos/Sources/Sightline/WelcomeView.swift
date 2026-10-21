import SwiftUI

struct WelcomeView: View {
    enum Step: Int, CaseIterable {
        case welcome, permissions, calibrate, tune, tryIt, done
        var title: String {
            switch self {
            case .welcome: "Hello"
            case .permissions: "Access"
            case .calibrate: "Screens"
            case .tune: "Tune"
            case .tryIt: "Test"
            case .done: "Done"
            }
        }
    }

    struct Actions {
        var showCameraPrivacy: () -> Void
        var askForCamera: () -> Void
        var askForAccessibility: () -> Void
        var calibrate: () -> Void
        var finish: () -> Void
    }

    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var state = LiveState.shared
    let actions: Actions
    @State var step: Step = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    content
                        .id(step)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 36).padding(.top, 36)
                footer
            }
            .background(Theme.panel)
        }
        .frame(width: 780, height: 540)
    }

    // MARK: Chrome

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AppMark(size: 28)
                Text("Sightline").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            }
            .padding(.bottom, 22)
            ForEach(Step.allCases, id: \.self) { s in
                let done = s.rawValue < step.rawValue
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(s == step ? Theme.brand : done ? Theme.brandTint : Theme.backdrop)
                        Circle().strokeBorder(s == step || done ? .clear : Theme.hairline)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.brand)
                        } else {
                            Text("\(s.rawValue + 1)").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(s == step ? Theme.onBrand : Theme.textFaint)
                        }
                    }
                    .frame(width: 20, height: 20)
                    Text(s.title).font(.system(size: 13, weight: s == step ? .semibold : .regular))
                        .foregroundStyle(s == step ? Theme.text : Theme.textMuted)
                }
                .padding(.vertical, 6)
            }
            Spacer()
            Text("About two minutes").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
        }
        .padding(22)
        .frame(width: 200, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.backdrop)
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") { go(-1) }.buttonStyle(OutlineButtonStyle())
            }
            Spacer()
            if let hint = footerHint {
                Text(hint).font(.system(size: 11.5)).foregroundStyle(Theme.textFaint)
            }
            Button(continueTitle) { step == .done ? actions.finish() : go(1) }
                .buttonStyle(FilledButtonStyle())
                .disabled(!canContinue)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 36).padding(.vertical, 20)
    }

    private var continueTitle: String {
        switch step {
        case .welcome: "Begin"
        case .done: "Finish"
        case .calibrate where !isCalibrated: "Later"
        default: "Next"
        }
    }

    private var canContinue: Bool {
        step != .permissions || (state.cameraAllowed && state.accessibilityAllowed)
    }

    private var footerHint: String? {
        step == .permissions && !canContinue ? "Both are needed" : nil
    }

    private var isCalibrated: Bool { !state.displays.isEmpty && state.unprofiled(prefs).isEmpty }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        withAnimation(Theme.snap) { step = next }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissions
        case .calibrate: calibrate
        case .tune: tune
        case .tryIt: tryIt
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 26) {
            Header(title: "Type where you look",
                   detail: "Sightline uses the Mac camera to see which screen, window or pane you face, and moves keyboard focus there. No more clicking before you type.")
            VStack(alignment: .leading, spacing: 16) {
                HowItWorks(icon: "display.2", title: "Face it", detail: "Turn to the screen, window or pane you want.")
                HowItWorks(icon: "web.camera", title: "Sightline sees it", detail: "The camera reads your head angle and pupils.")
                HowItWorks(icon: "keyboard", title: "Type", detail: "Your keystrokes land there. No click.")
            }
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.brand)
                HStack(spacing: 4) {
                    Text("Press")
                    KeyGlyphs(keys: prefs.shortcut.keys)
                    Text("or use the menu bar icon to pause.")
                }
            }
            .font(.system(size: 12.5)).foregroundStyle(Theme.textMuted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.backdrop, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Two things to allow",
                   detail: "macOS asks once for each. Until you allow them, Sightline cannot see or move anything.")
            Tile {
                AccessRow(icon: "camera.fill", title: "Camera",
                              detail: "To see which way you face. Frames stay in memory.",
                              granted: state.cameraAllowed, action: actions.askForCamera)
                Divider().padding(.leading, 56)
                AccessRow(icon: "accessibility", title: "Accessibility",
                              detail: "To raise the window you look at and move the pointer.",
                              granted: state.accessibilityAllowed, action: actions.askForAccessibility)
            }
            Text(canContinue ? "Done. Press Next."
                 : "Turn Sightline on under System Settings, Privacy & Security. This page refreshes on its own.")
                .font(.system(size: 12)).foregroundStyle(canContinue ? Theme.brand : Theme.textFaint)
            if !state.accessibilityAllowed {
                // macOS keeps a stale entry when the app's signature changes; the switch then shows on but does nothing.
                Text("Switch on but nothing happens? Remove Sightline from the Accessibility list with the minus button, then press Allow again.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calibrate: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Show Sightline your screens",
                   detail: "Sightline learns where each screen sits, as seen from your chair.")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Bullet("Each screen turns bright and shows a dot.")
                    Bullet("Press Space. Follow the dot with head and eyes, then with eyes only.")
                    Bullet("About 30 seconds per screen.")
                    Bullet("Sit as you normally work.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FaceStatus()
                    .frame(width: 220)
            }
            HStack(spacing: 12) {
                Button(isCalibrated ? "Redo Setup" : "Start Setup", action: actions.calibrate)
                    .buttonStyle(FilledButtonStyle())
                    .disabled(!state.seesFace)
                if isCalibrated {
                    Label("Every screen is set up", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.brand)
                } else if state.displays.isEmpty {
                    Text("No screen found. You can do this later from the menu bar.")
                        .font(.system(size: 12)).foregroundStyle(Theme.caution)
                }
            }
        }
    }

    private var tune: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Tune the feel", detail: "The defaults work for most people. Preferences can change them later.")
            Tile {
                SwitchRow(icon: "rectangle.split.3x1", title: "Follow windows and panes", detail: "Not only screens: windows and split panes too.",
                          info: nil, isOn: $prefs.followWithinScreen)
                Divider().padding(.leading, 14)
                SwitchRow(icon: "keyboard", title: "Hold focus while typing", detail: "Keystrokes stay where you type.",
                          info: nil, isOn: $prefs.holdWhileTyping)
                Divider().padding(.leading, 14)
                SwitchRow(icon: "scope", title: "Learn from clicks", detail: "Clicks fine-tune the setup.",
                          info: nil, isOn: $prefs.learnFromMyClicks)
                Divider().padding(.leading, 14)
                RangeRow(title: "Switch delay", detail: "Shorter looks than this do not switch.", info: nil,
                          value: $prefs.switchDelayMs, range: 100...1000, step: 50, format: { "\(Int($0)) ms" })
            }
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Try it now",
                   detail: "Look from screen to screen. The map marks the screen you face, and the dot shows about where you look.")
            Tile { ScreenMap(height: 170).padding(16) }
            if !isCalibrated {
                Label("Set up your screens first (step 3).", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.caution)
            } else {
                Text(state.summary(prefs)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.brand)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 22) {
            Header(title: "Sightline runs from the menu bar",
                   detail: "There is no Dock icon. Use these to reach it.")
            Tile {
                HStack(spacing: 12) {
                    Image(systemName: "eye").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.brand)
                        .frame(width: 32, height: 32).background(Theme.brandTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Click the menu bar icon to pause, redo setup or open Preferences.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                Divider().padding(.leading, 58)
                HStack(spacing: 12) {
                    Image(systemName: "command").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.brand)
                        .frame(width: 32, height: 32).background(Theme.brandTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    HStack(spacing: 5) {
                        Text("Press")
                        KeyGlyphs(keys: prefs.shortcut.keys)
                        Text("in any app to pause or resume.")
                    }
                    .font(.system(size: 13)).foregroundStyle(Theme.text)
                }
                .padding(14)
            }
            SwitchRow(icon: "power", title: "Open at login", detail: "Start Sightline when you log in.",
                      info: nil, isOn: Binding(get: { prefs.openAtLogin }, set: { prefs.openAtLogin = $0 }))
                .background(Theme.backdrop, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Camera frames stay in memory on this Mac. Nothing is stored or sent.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textFaint)
        }
    }
}

// MARK: - Pieces

private struct Header: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(.system(size: 13.5)).foregroundStyle(Theme.textMuted)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 480, alignment: .leading)
        }
    }
}

private struct HowItWorks: View {
    let icon: String
    let title: String
    let detail: String
    var body: some View {
        Label { Text(title) } icon: { Image(systemName: icon) }.labelStyle(RowLabelStyle(detail: detail))
    }
}

private struct Bullet: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Theme.brand).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct AccessRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label { Text(title) } icon: { Image(systemName: icon) }.labelStyle(RowLabelStyle(detail: detail))
            Spacer(minLength: 12)
            if granted {
                Badge(text: "Allowed", kind: .good).transition(.opacity)
            } else {
                Button("Allow…", action: action).buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(14)
        .animation(Theme.snap, value: granted)
    }
}

/// Live camera status for the session step.
private struct FaceStatus: View {
    @ObservedObject var state = LiveState.shared
    var body: some View {
        let (icon, text, kind): (String, String, Badge.Kind) =
            !state.cameraAllowed ? ("video.slash", "Allow the camera in step 2 first.", .warn)
            : state.cameraProblem != nil ? ("exclamationmark.triangle", "The camera is not working. Choose another in Preferences.", .warn)
            : state.seesFace ? ("face.smiling", "Face in view. Ready.", .good)
            : ("person.crop.circle.dashed", "Looking for a face…", .idle)
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 26, weight: .light))
                .foregroundStyle(kind == .good ? Theme.brand : kind == .warn ? Theme.caution : Theme.textFaint)
                .contentTransition(.symbolEffect(.replace))
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .background(Theme.backdrop, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(Theme.snap, value: text)
    }
}
