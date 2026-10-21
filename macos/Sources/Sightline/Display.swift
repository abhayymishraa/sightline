import AppKit

/// One connected screen. `frame` is in global CoreGraphics points (origin top-left of the main display, y down),
/// the space that CGEvent, CGWarpMouseCursorPosition and the Accessibility API use.
struct Display: Identifiable, Equatable {
    let id: String          // stable display UUID, survives reboots and re-plugging
    let displayID: CGDirectDisplayID
    let name: String
    let frame: CGRect

    static func all() -> [Display] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
            return Display(
                id: CFUUIDCreateString(nil, uuid) as String,
                displayID: displayID,
                name: screen.localizedName,
                frame: CGDisplayBounds(displayID)
            )
        }
    }

    var screen: NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }
    }

    /// Converts a point in this display's unit square (0...1, y down) to global points.
    func point(_ unit: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + unit.x * frame.width, y: frame.minY + unit.y * frame.height)
    }

    /// Converts a global point to this display's unit square.
    func unit(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
    }
}
