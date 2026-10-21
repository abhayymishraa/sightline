import AppKit
import SwiftUI

/// Development aid: `Sightline --snapshot DIR` renders every window to PNG in light and dark mode, then exits.
enum Snapshot {
    @MainActor static func run(to dir: String) {
        let noop = {}
        let onboarding = WelcomeView.Actions(showCameraPrivacy: noop, askForCamera: noop, askForAccessibility: noop, calibrate: noop, finish: noop)
        var views: [(String, AnyView)] = WelcomeView.Step.allCases.map {
            ("welcome-\($0.rawValue)", AnyView(WelcomeView(actions: onboarding, step: $0)))
        }
        views.append(("preferences", AnyView(PreferencesView(actions: .init(calibrate: noop, calibrateNewScreens: noop, showCameraPrivacy: noop, askForAccessibility: noop)))))
        let model = CalibrationSession.Model()
        model.title = "Follow the dot as you naturally would"
        model.subtitle = "8 spots on this screen, about 20 seconds."
        model.screenLabel = "Screen 1 of 2: DELL S2725HSM"
        views.append(("calibration-ready", AnyView(CalibrationCanvas(model: model).frame(width: 1280, height: 800))))
        let running = CalibrationSession.Model()
        running.phase = .running; running.title = "Keep watching the dot"; running.subtitle = "Spot 2 of 4"
        running.spot = CGPoint(x: 0.97, y: 0.5); running.spotProgress = 0.6; running.progress = 0.3
        views.append(("calibration-running", AnyView(CalibrationCanvas(model: running).frame(width: 1280, height: 800))))

        for (name, view) in views {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                window.setContentSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(suffix).png"))
            }
        }
    }
}
