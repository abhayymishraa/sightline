import SwiftUI
import AVFoundation

struct PreferencesView: View {
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var state = LiveState.shared
    let actions: Actions

    struct Actions {
        var calibrate: () -> Void
        var calibrateNewScreens: () -> Void
        var showCameraPrivacy: () -> Void
        var askForAccessibility: () -> Void
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                statusCard
                section("Switching screens") {
                    RangeRow(title: "Delay before switching", detail: "Shorter looks than this do not switch.",
                              info: "Time you must face another screen before focus moves to it. Short is quick; long ignores brief looks.",
                              value: $prefs.switchDelayMs, range: 100...1000, step: 50, format: { "\(Int($0)) ms" })
                    Divider().padding(.leading, 14)
                    RangeRow(title: "Head turn needed", detail: "How far your head turns before the next screen wins.",
                              info: "The boundary between two screens, as a share of the distance between their nearest setup spots. Low values switch with a small turn; high values need a bigger turn and keep focus steady when you look at a screen edge.",
                              value: $prefs.boundary, range: 0.2...0.8, step: 0.05, format: { "\(Int(($0 * 100).rounded()))%" })
                }
                section("Within the same screen") {
                    SwitchRow(icon: "rectangle.split.3x1", title: "Focus the window or pane I look at",
                              detail: "Windows side by side and split panes in terminals and editors.",
                              info: "On the screen you face, focus moves between side-by-side windows and between split panes in terminals and code editors such as iTerm2, Terminal, Ghostty, VS Code, Cursor and Xcode. Windows that overlap never switch.",
                              isOn: $prefs.followWithinScreen)
                    if prefs.followWithinScreen {
                        Divider().padding(.leading, 14)
                        RangeRow(title: "Pane delay", detail: "Look time before a pane gets focus.",
                                  info: "Time you must look at another window or pane on this screen before it gets focus.",
                                  value: $prefs.paneDelayMs, range: 100...1000, step: 50, format: { "\(Int($0)) ms" })
                        Divider().padding(.leading, 14)
                        SwitchRow(icon: "cursorarrow.click.2", title: "Click to focus panes when needed",
                                  detail: "Only in terminals and editors.",
                                  info: "Some terminals and editors ignore requests to focus a split pane. Then Sightline clicks the centre of the pane and puts the pointer back. It never clicks in other apps. In an editor, the click also moves the text cursor.",
                                  isOn: $prefs.clickToFocusPanes)
                    }
                }
                section("Typing and accuracy") {
                    SwitchRow(icon: "keyboard", title: "Wait while I'm typing", detail: "Keystrokes stay where you type.",
                              info: "While you type, focus does not move, so a quick look at another pane cannot take your keystrokes.",
                              isOn: $prefs.holdWhileTyping)
                    if prefs.holdWhileTyping {
                        Divider().padding(.leading, 14)
                        RangeRow(title: "Hold time", detail: "Time after the last keystroke.",
                                  info: "Long values cover pauses to think; short values let focus follow you again sooner.",
                                  value: $prefs.typingHoldSeconds, range: 0.5...5, step: 0.25, format: { String(format: "%.2g s", $0) })
                    }
                    Divider().padding(.leading, 14)
                    SwitchRow(icon: "scope", title: "Learn from my clicks", detail: "Clicks fine-tune the setup.",
                              info: "You look where you click, so each click on the screen you face becomes a new reference point. This keeps the setup accurate when you move closer, farther or to one side. Redoing the setup clears what was learned.",
                              isOn: $prefs.learnFromMyClicks)
                    Divider().padding(.leading, 14)
                    SwitchRow(icon: "smallcircle.filled.circle", title: "Show gaze dot", detail: "A rough mark of where Sightline thinks you look.",
                              info: "A webcam can tell the screen and the rough area you look at, so the marker can sit a few centimetres off and move a little. Use it to check the setup.",
                              isOn: $prefs.showGazeMarker)
                }
                section("Camera and setup") {
                    cameraRow
                    Divider().padding(.leading, 14)
                    calibrationRow
                }
                section("General") {
                    HStack {
                        Label { Text("Pause / resume shortcut") } icon: { Image(systemName: "command") }
                            .labelStyle(RowLabelStyle(detail: "Works from any app."))
                        Spacer()
                        ShortcutField(combo: $prefs.shortcut)
                    }
                    .padding(14)
                    Divider().padding(.leading, 14)
                    SwitchRow(icon: "power", title: "Open at login", detail: "Start Sightline when you log in.",
                              info: nil, isOn: Binding(get: { prefs.openAtLogin }, set: { prefs.openAtLogin = $0 }))
                }
                Text("Sightline reads camera frames in memory. It never stores or sends them.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .background(Theme.backdrop)
        .frame(width: 560, height: 680)
    }

    private var statusCard: some View {
        Tile {
            HStack(spacing: 12) {
                AppMark(size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sightline").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(state.summary(prefs)).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                        .contentTransition(.opacity)
                }
                Spacer()
                Toggle("", isOn: $prefs.active).toggleStyle(.switch).labelsHidden().tint(Theme.brand)
            }
            .padding(14)
            Divider()
            ScreenMap(height: 110).padding(14)
            if let pose = state.pose {
                HStack(spacing: 16) {
                    Readout(label: "Yaw", value: pose.yaw)
                    Readout(label: "Pitch", value: pose.pitch)
                    Spacer()
                    Text("Live from the camera").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 14).padding(.bottom, 12)
            }
        }
    }

    private var cameraRow: some View {
        HStack {
            Label { Text("Camera") } icon: { Image(systemName: "camera") }
                .labelStyle(RowLabelStyle(detail: "Pick the camera in front of you."))
            Spacer()
            if state.cameraAllowed {
                Picker("", selection: $prefs.cameraChoice) {
                    Text("Automatic").tag(String?.none)
                    ForEach(state.cameras, id: \.uniqueID) { Text($0.localizedName).tag(String?.some($0.uniqueID)) }
                }
                .labelsHidden().frame(width: 200)
            } else {
                Button("Allow Camera…", action: actions.showCameraPrivacy).buttonStyle(OutlineButtonStyle())
            }
        }
        .padding(14)
    }

    private var calibrationRow: some View {
        let missing = state.unprofiled(prefs)
        let calibrated = state.displays.count - missing.count
        return HStack {
            Label { Text("Screen setup") } icon: { Image(systemName: "display.2") }
                .labelStyle(RowLabelStyle(detail: calibrated == 0
                    ? "Show Sightline where your screens are."
                    : "Redo it after you move a screen or your laptop."))
            Spacer()
            if !missing.isEmpty && calibrated > 0 {
                Button("Set Up New…", action: actions.calibrateNewScreens).buttonStyle(OutlineButtonStyle())
            }
            Button(calibrated == 0 ? "Set Up…" : "Redo Setup…", action: actions.calibrate)
                .buttonStyle(FilledButtonStyle())
                .disabled(!state.cameraAllowed)
        }
        .padding(14)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).padding(.leading, 2)
            Tile { content() }
        }
    }
}

private struct Readout: View {
    let label: String
    let value: Double
    var body: some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(Theme.textFaint)
            Text(String(format: "%+.1f°", value)).foregroundStyle(Theme.text).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
    }
}

struct RowLabelStyle: LabelStyle {
    var detail: String
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.brand)
                .frame(width: 26, height: 26)
                .background(Theme.brandTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                configuration.title.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SwitchRow: View {
    let icon: String
    let title: String
    let detail: String
    let info: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label { Text(title) } icon: { Image(systemName: icon) }.labelStyle(RowLabelStyle(detail: detail))
            if let info { HelpButton(text: info) }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small).tint(Theme.brand)
        }
        .padding(14)
    }
}

struct RangeRow: View {
    let title: String
    let detail: String
    let info: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                if let info { HelpButton(text: info) }
                Spacer()
                Text(format(value)).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.brand)
            }
            // Continuous slider (no tick marks); the stored value snaps to `step`.
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range)
                .tint(Theme.brand).controlSize(.small)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
        }
        .padding(14)
    }
}

struct HelpButton: View {
    let text: String
    @State private var shown = false
    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
        }
        .buttonStyle(.plain)
        .help("Details")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text)
                .frame(width: 280, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(14)
        }
    }
}

/// Click, then press a combination with ⌘, ⌥ or ⌃. Esc cancels.
struct ShortcutField: View {
    @Binding var combo: Shortcut
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Group {
                if recording {
                    Text("Press keys…").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.brand)
                        .padding(.horizontal, 8).frame(height: 24)
                } else {
                    KeyGlyphs(keys: combo.keys)
                }
            }
            .padding(2)
            .background(recording ? Theme.brandTint : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }      // Esc
            if let c = Shortcut(event: event) { combo = c; stop() } else { NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
