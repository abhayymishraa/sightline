import AppKit
import AVFoundation
import Combine
import SwiftUI
import GazeCore
import os

let log = Logger(subsystem: "dev.sightline.Sightline", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let prefs = Preferences.shared
    private let state = LiveState.shared
    private let tracker = FaceTracker()
    private let picker = ScreenPicker()
    private let mover = FocusMover()
    private let marker = GazeMarker()
    private var misses = MissCounter()

    private var statusItem: NSStatusItem!
    private var shortcutBinding: GlobalShortcut?
    private var session: CalibrationSession?
    private var preferencesWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private var cameraRunning = false
    private var bag: Set<AnyCancellable> = []

    private var lastPose: (pose: HeadPose, time: Double)?
    private var gazeFilter = (x: OneEuroFilter(minCutoff: 0.6, beta: 0.004), y: OneEuroFilter(minCutoff: 0.6, beta: 0.004))
    private var gazeScreen: String?
    private var pending: (target: FocusCandidate, since: Double)?
    private var frameCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        tracker.onFrame = { [weak self] in self?.process($0) }
        tracker.onProblem = { [weak self] error in
            log.info("camera status: \(error ?? "frames flowing", privacy: .public)")
            self?.state.cameraProblem = error
        }
        log.info("launch camera=\(self.state.cameraAllowed) accessibility=\(self.state.accessibilityAllowed)")

        refreshScreens()
        watchSystem()
        bindShortcut()
        mover.start()
        refresh()

        if !prefs.welcomeFinished { openWelcome() }
    }

    // MARK: Per-frame pipeline

    private func process(_ reading: FaceTracker.Frame) {
        if let session, session.isActive {
            session.add(reading)
            if case .face(let p) = reading { state.pose = p } else { state.pose = nil }
            return
        }
        guard case .face(let pose) = reading else {
            state.pose = nil
            picker.reset()
            pending = nil
            marker.hide()
            return
        }
        state.pose = pose
        guard isRunning else { marker.hide(); return }

        let now = CACurrentMediaTime()
        lastPose = (pose, now)
        let cals = activeProfiles
        guard !cals.isEmpty else { return }

        let screens = cals.mapValues { $0.shiftedAnchors(for: pose) }
        let reference = cals.values.map(\.baseFaceSize).reduce(0, +) / Double(cals.count)
        let np = pose.scaled(toFaceSize: reference)
        let head = HeadAngle(yaw: np.yaw, pitch: np.pitch)

        // What the user faces right now, for the map and the gaze point.
        let facing = screens.min { a, b in Self.distance(head, a.value) < Self.distance(head, b.value) }?.key
        state.lookingAtID = picker.screen ?? facing
        let gp = facing.flatMap { id in state.displays.first { $0.id == id } }.flatMap { filteredGaze(pose, on: $0, cals) }
        state.gaze = gp
        if prefs.showGazeMarker, let gp { marker.show(at: gp) } else { marker.hide() }

        // Typing or mouse use: focus belongs where the user put it.
        let sinceKey = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        if (prefs.holdWhileTyping && sinceKey < prefs.typingHoldSeconds) || pointerBusy() {
            if let current = focusedScreenID() { picker.pin(current) }
            pending = nil
            return
        }

        if let id = picker.step(head: head, anchors: screens, delay: prefs.switchDelayMs / 1000,
                                      boundary: prefs.boundary, now: now,
                                      pupils: { [weak self] in self?.pupilVote(pose, to: $0, cals) }),
           let display = state.displays.first(where: { $0.id == id }) {
            state.lookingAtID = id
            pending = nil
            mover.bringForward(display, near: prefs.followWithinScreen ? gazeLocation(pose, on: display, cals) : nil)
            return
        }

        // Within one screen: about 7 checks per second are plenty for a dwell of a few hundred ms.
        frameCount += 1
        guard prefs.followWithinScreen, let gp, frameCount % 2 == 0 else { return }
        guard let target = mover.candidate(at: gp) else { pending = nil; return }
        if let p = pending, target.same(as: p.target) {
            if now - p.since >= prefs.paneDelayMs / 1000 {
                pending = nil
                mover.apply(target, clickToFocusPanes: prefs.clickToFocusPanes)
            }
        } else {
            pending = (target, now)
        }
    }

    private var isRunning: Bool {
        prefs.active && !state.isLocked && state.accessibilityAllowed && !state.displays.isEmpty
            && (state.displays.count > 1 || prefs.followWithinScreen)
    }

    /// Calibrations of displays that are connected now.
    private var activeProfiles: [String: ScreenProfile] {
        prefs.profiles.filter { id, _ in state.displays.contains { $0.id == id } }
    }

    private static func distance(_ p: HeadAngle, _ dots: [HeadAngle]) -> Double {
        dots.map { hypot($0.yaw - p.yaw, $0.pitch - p.pitch) }.min() ?? .infinity
    }

    private func gazeLocation(_ pose: HeadPose, on d: Display, _ cals: [String: ScreenProfile]) -> CGPoint? {
        cals[d.id]?.locate(pose).map(d.point)
    }

    private func filteredGaze(_ pose: HeadPose, on d: Display, _ cals: [String: ScreenProfile]) -> CGPoint? {
        guard let raw = gazeLocation(pose, on: d, cals) else { return nil }
        if gazeScreen != d.id {
            gazeScreen = d.id
            gazeFilter.x.reset(); gazeFilter.y.reset()
        }
        let t = CACurrentMediaTime()
        return CGPoint(x: gazeFilter.x.filter(raw.x, at: t), y: gazeFilter.y.filter(raw.y, at: t))
    }

    /// Eyes break ties near a boundary: they vote for a screen when its eye model puts the gaze inside it
    /// and the current screen's model puts it outside.
    private func pupilVote(_ pose: HeadPose, to target: String, _ cals: [String: ScreenProfile]) -> Bool? {
        func margin(_ id: String?) -> Double? {
            guard let id, let cal = cals[id], let model = cal.pupilModel,
                  let f = pose.features(baseFaceSize: cal.baseFaceSize, withPupils: true) else { return nil }
            let p = model.map(f)
            return min(p.x, 1 - p.x, p.y, 1 - p.y)
        }
        guard let there = margin(target), let here = margin(picker.screen) else { return nil }
        if there > 0.02 && here < -0.02 { return true }
        if here > 0.02 && there < -0.02 { return false }
        return nil
    }

    private func pointerBusy() -> Bool {
        if NSEvent.pressedMouseButtons != 0 { return true }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min()! < 1.5
    }

    private func focusedScreenID() -> String? {
        if let w = mover.frontWindow(), let f = FocusMover.frame(w), let d = mover.screen(containing: f) { return d.id }
        let mouse = FocusMover.mouseLocation
        return state.displays.first { $0.frame.contains(mouse) }?.id
    }

    // MARK: Clicks: misses detection and learning

    private func clicked() {
        let point = FocusMover.mouseLocation
        guard let display = state.displays.first(where: { $0.frame.contains(point) }) else { return }
        picker.pin(display.id)
        guard isRunning, let last = lastPose, CACurrentMediaTime() - last.time < 0.25,
              var cal = prefs.profiles[display.id] else { return }
        let unit = display.unit(point)
        if let guess = cal.locate(last.pose) {
            let miss = hypot(guess.x - unit.x, guess.y - unit.y) > 0.35
            if misses.note(screen: display.id, miss: miss) { state.unreliableIDs.insert(display.id); refresh() }
        }
        guard prefs.learnFromMyClicks else { return }
        cal.absorbClick(pose: last.pose, at: unit)
        prefs.profiles[display.id] = cal
    }

    // MARK: System

    private func watchSystem() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked() }
        }
        let nc = NotificationCenter.default
        nc.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refreshScreens() }.store(in: &bag)
        nc.publisher(for: AVCaptureDevice.wasConnectedNotification).merge(with: nc.publisher(for: AVCaptureDevice.wasDisconnectedNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                state.cameras = FaceTracker.cameras()
                cameraRunning = false
                matchCamera()
            }.store(in: &bag)
        // Capture sessions do not always survive sleep.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification).receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.cameraRunning = false
                self?.refresh()
            }.store(in: &bag)
        let dnc = DistributedNotificationCenter.default()
        dnc.publisher(for: .init("com.apple.screenIsLocked")).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.state.isLocked = true; self?.refresh() }.store(in: &bag)
        dnc.publisher(for: .init("com.apple.screenIsUnlocked")).receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.state.isLocked = false; self?.refresh() }.store(in: &bag)

        // Settings that change what runs.
        prefs.$active.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &bag)
        prefs.$cameraChoice.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.cameraRunning = false
            self?.refresh()
        }.store(in: &bag)
        prefs.$shortcut.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in self?.bindShortcut() }.store(in: &bag)

        // Permissions can change in System Settings at any time; polling is the only signal.
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let camera = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
                let ax = AXIsProcessTrusted()
                if camera != self.state.cameraAllowed || ax != self.state.accessibilityAllowed {
                    log.info("permissions camera=\(camera) accessibility=\(ax)")
                    self.state.cameraAllowed = camera
                    self.state.accessibilityAllowed = ax
                    self.refresh()
                }
            }
        }
    }

    private func refreshScreens() {
        state.displays = Display.all()
        mover.displays = state.displays
        picker.reset()
        // A calibrated screen that moved relative to the others: focus may miss until recalibrated.
        let moved = state.displays.filter { d in prefs.profiles[d.id]?.frame.map { $0 != d.frame } ?? false }
        state.screensMoved = !moved.isEmpty
        misses.suspect = Set(moved.map(\.id))
        refresh()
    }

    private func bindShortcut() {
        shortcutBinding = nil
        shortcutBinding = GlobalShortcut(prefs.shortcut) { [weak self] in self?.toggleActive() }
    }

    /// Starts or stops the camera to match what is needed now. The camera light stays off while paused.
    private func matchCamera() {
        let windowsOpen = preferencesWindow?.isVisible == true || welcomeWindow?.isVisible == true || session != nil
        let want = state.cameraAllowed && !state.isLocked && (prefs.active || windowsOpen)
        prefs.cameraInUse = FaceTracker.camera(for: prefs.cameraChoice)?.uniqueID ?? ""
        if want != cameraRunning { log.info("camera \(want ? "start" : "stop", privacy: .public) id=\(self.prefs.cameraInUse, privacy: .public)") }
        if want && !cameraRunning {
            tracker.start(cameraChoice: prefs.cameraChoice)
        } else if !want && cameraRunning {
            tracker.stop()
            state.pose = nil
            marker.hide()
        }
        cameraRunning = want
    }

    private func refresh() {
        matchCamera()
        paintStatusIcon()
    }

    private func paintStatusIcon() {
        let symbol: String
        switch state.mode(prefs) {
        case .tracking, .lookingForFace: symbol = state.unreliableIDs.isEmpty ? "eye" : "eye.trianglebadge.exclamationmark"
        case .paused, .locked, .oneDisplay, .noDisplay: symbol = "eye.slash"
        default: symbol = "eye.trianglebadge.exclamationmark"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sightline")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "Sightline: \(state.summary(prefs))"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: state.summary(prefs), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if state.screensMoved {
            menu.addItem(disabled: "Your screens moved. Redo setup if focus lands wrong")
        }
        for id in state.unreliableIDs {
            if let d = state.displays.first(where: { $0.id == id }) { menu.addItem(disabled: "\(d.name): focus often misses") }
        }
        menu.addItem(.separator())

        let pause = menu.addItem(withTitle: prefs.active ? "Pause" : "Resume", action: #selector(toggleActive), keyEquivalent: "")
        pause.target = self
        if !state.cameraAllowed { menu.addItem(action: "Allow Camera…", #selector(showCameraPrivacy), target: self) }
        if !state.accessibilityAllowed { menu.addItem(action: "Allow Accessibility…", #selector(askForAccessibility), target: self) }
        menu.addItem(.separator())

        let missing = state.unprofiled(prefs)
        let anyCalibrated = missing.count < state.displays.count
        if !missing.isEmpty && anyCalibrated {
            menu.addItem(action: "Set Up \(missing.map(\.name).joined(separator: ", "))…", #selector(calibrateNewScreens), target: self)
        }
        menu.addItem(action: anyCalibrated ? (state.unreliableIDs.isEmpty ? "Redo Setup…" : "Redo Setup (Recommended)…") : "Set Up Screens…",
                     #selector(calibrateEverything), target: self)
        menu.addItem(action: "Preferences…", #selector(openPreferences), target: self, key: ",")
        menu.addItem(action: "Getting Started…", #selector(openWelcome), target: self)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Sightline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func toggleActive() {
        prefs.active.toggle()
        if !prefs.active { picker.reset(); pending = nil; marker.hide() }
    }

    @objc func showCameraPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
    }

    @objc func askForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private func askForCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.state.cameraAllowed = granted
                    self.refresh()
                }
            }
        case .authorized: break
        default: showCameraPrivacy()
        }
    }

    // MARK: Calibration

    @objc func calibrateEverything() { calibrate(state.displays) }
    @objc func calibrateNewScreens() { calibrate(state.unprofiled(prefs)) }

    private func calibrate(_ displays: [Display]) {
        guard !displays.isEmpty, session == nil else { return }
        let controller = CalibrationSession(displays: displays, allDisplays: state.displays) { [weak self] results in
            guard let self else { return }
            session = nil
            if let results {
                var all = prefs.profiles
                all.merge(results) { $1 }
                prefs.profiles = all
                for id in results.keys { misses.forget(id); state.unreliableIDs.remove(id) }
                misses.suspect.subtract(results.keys)
                state.screensMoved = state.displays.contains { d in all[d.id]?.frame.map { $0 != d.frame } ?? false }
                picker.reset()
            }
            refresh()
            (welcomeWindow?.isVisible == true ? welcomeWindow : preferencesWindow?.isVisible == true ? preferencesWindow : nil)?
                .makeKeyAndOrderFront(nil)
        }
        session = controller
        refresh()
        controller.start()
    }

    // MARK: Windows

    @objc func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView(actions: .init(
                calibrate: { [weak self] in self?.calibrateEverything() },
                calibrateNewScreens: { [weak self] in self?.calibrateNewScreens() },
                showCameraPrivacy: { [weak self] in self?.showCameraPrivacy() },
                askForAccessibility: { [weak self] in self?.askForAccessibility() }))
            preferencesWindow = makeWindow(title: "Sightline Preferences", view: view, transparentTitle: false)
        }
        present(preferencesWindow!)
    }

    @objc func openWelcome() {
        if welcomeWindow == nil {
            let view = WelcomeView(actions: .init(
                showCameraPrivacy: { [weak self] in self?.showCameraPrivacy() },
                askForCamera: { [weak self] in self?.askForCamera() },
                askForAccessibility: { [weak self] in self?.askForAccessibility() },
                calibrate: { [weak self] in self?.calibrateEverything() },
                finish: { [weak self] in
                    self?.prefs.welcomeFinished = true
                    self?.welcomeWindow?.close()
                }))
            welcomeWindow = makeWindow(title: "Getting Started", view: view, transparentTitle: true)
        }
        present(welcomeWindow!)
    }

    private func makeWindow<V: View>(title: String, view: V, transparentTitle: Bool) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = title
        w.styleMask = [.titled, .closable, .miniaturizable]
        if transparentTitle {
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
        }
        w.isReleasedWhenClosed = false
        NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: w)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &bag)
        return w
    }

    private func present(_ w: NSWindow) {
        w.center()
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        refresh()
    }
}

private extension NSMenu {
    @discardableResult
    func addItem(action title: String, _ selector: Selector, target: AnyObject, key: String = "") -> NSMenuItem {
        let item = addItem(withTitle: title, action: selector, keyEquivalent: key)
        item.target = target
        return item
    }

    func addItem(disabled title: String) {
        let item = addItem(withTitle: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
    }
}

/// A small click-through dot that marks the estimated gaze point.
@MainActor
final class GazeMarker {
    private lazy var panel: NSPanel = {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 22, height: 22),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = NSHostingView(rootView:
            Circle().fill(Theme.brand.opacity(0.55))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                .frame(width: 22, height: 22))
        return p
    }()

    /// `point` is in global top-left coordinates.
    func show(at point: CGPoint) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrameOrigin(NSPoint(x: point.x - 11, y: primaryHeight - point.y - 11))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() { if panel.isVisible { panel.orderOut(nil) } }
}
