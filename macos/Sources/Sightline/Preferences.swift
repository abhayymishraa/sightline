import Foundation
import ServiceManagement
import GazeCore

/// User preferences, stored in UserDefaults. Screen profiles are kept per camera,
/// because each camera sees the head from a different angle.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let store = UserDefaults.standard

    @Published var active: Bool { didSet { store.set(active, forKey: Key.active) } }
    @Published var switchDelayMs: Double { didSet { store.set(switchDelayMs, forKey: Key.switchDelay) } }
    @Published var boundary: Double { didSet { store.set(boundary, forKey: Key.boundary) } }
    @Published var followWithinScreen: Bool { didSet { store.set(followWithinScreen, forKey: Key.followWithin) } }
    @Published var paneDelayMs: Double { didSet { store.set(paneDelayMs, forKey: Key.paneDelay) } }
    @Published var clickToFocusPanes: Bool { didSet { store.set(clickToFocusPanes, forKey: Key.paneClick) } }
    @Published var holdWhileTyping: Bool { didSet { store.set(holdWhileTyping, forKey: Key.typingHold) } }
    @Published var typingHoldSeconds: Double { didSet { store.set(typingHoldSeconds, forKey: Key.typingHoldSeconds) } }
    @Published var learnFromMyClicks: Bool { didSet { store.set(learnFromMyClicks, forKey: Key.learnClicks) } }
    @Published var showGazeMarker: Bool { didSet { store.set(showGazeMarker, forKey: Key.marker) } }
    @Published var cameraChoice: String? { didSet { store.set(cameraChoice, forKey: Key.camera) } }
    @Published var shortcut: Shortcut { didSet { store.set(try? JSONEncoder().encode(shortcut), forKey: Key.shortcut) } }
    @Published var welcomeFinished: Bool { didSet { store.set(welcomeFinished, forKey: Key.welcome) } }

    /// [camera uniqueID: [screen UUID: profile]]
    @Published private var profilesByCamera: [String: [String: ScreenProfile]] {
        didSet { store.set(try? JSONEncoder().encode(profilesByCamera), forKey: Key.profiles) }
    }

    /// The camera that runs now; set when the camera starts.
    @Published var cameraInUse = ""

    /// Screen profiles for the camera in use.
    var profiles: [String: ScreenProfile] {
        get { profilesByCamera[cameraInUse] ?? [:] }
        set { profilesByCamera[cameraInUse] = newValue }
    }

    private enum Key {
        static let active = "sl.active"
        static let switchDelay = "sl.switchDelayMs"
        static let boundary = "sl.boundary"
        static let followWithin = "sl.followWithinScreen"
        static let paneDelay = "sl.paneDelayMs"
        static let paneClick = "sl.clickToFocusPanes"
        static let typingHold = "sl.holdWhileTyping"
        static let typingHoldSeconds = "sl.typingHoldSeconds"
        static let learnClicks = "sl.learnFromClicks"
        static let marker = "sl.showGazeMarker"
        static let camera = "sl.camera"
        static let shortcut = "sl.shortcut"
        static let welcome = "sl.welcomeFinished"
        static let profiles = "sl.profiles"
    }

    private init() {
        store.register(defaults: [
            Key.active: true, Key.switchDelay: 300.0, Key.boundary: 0.5, Key.followWithin: true,
            Key.paneDelay: 200.0, Key.paneClick: true, Key.typingHold: true, Key.typingHoldSeconds: 2.0,
            Key.learnClicks: true, Key.marker: false,
        ])
        active = store.bool(forKey: Key.active)
        switchDelayMs = store.double(forKey: Key.switchDelay)
        boundary = store.double(forKey: Key.boundary)
        followWithinScreen = store.bool(forKey: Key.followWithin)
        paneDelayMs = store.double(forKey: Key.paneDelay)
        clickToFocusPanes = store.bool(forKey: Key.paneClick)
        holdWhileTyping = store.bool(forKey: Key.typingHold)
        typingHoldSeconds = store.double(forKey: Key.typingHoldSeconds)
        learnFromMyClicks = store.bool(forKey: Key.learnClicks)
        showGazeMarker = store.bool(forKey: Key.marker)
        cameraChoice = store.string(forKey: Key.camera)
        welcomeFinished = store.bool(forKey: Key.welcome)
        shortcut = store.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .default
        profilesByCamera = store.data(forKey: Key.profiles)
            .flatMap { try? JSONDecoder().decode([String: [String: ScreenProfile]].self, from: $0) } ?? [:]
    }

    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
