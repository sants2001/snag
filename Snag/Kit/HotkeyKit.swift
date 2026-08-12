//
//  The global hotkey layer, replacing Lowtech's.
//
//  Built on Magnet (Carbon hotkey registration) and Sauce (layout-independent key codes), both
//  MIT and both already direct dependencies. Lowtech contributed only the glue: a trigger-key
//  enum, a few SauceKey conveniences, and the manager that ties a key plus modifiers to a
//  callback.
//
//  This is the part of the app a user touches first and most often, and it has no test
//  coverage, so behaviour is matched deliberately rather than reinvented.
//

import Carbon
import Defaults
import OSLog
import Magnet
import Sauce
import SwiftUI

/// Sauce's `Key`, under the name the rest of the app already uses.
typealias SauceKey = Key

// MARK: - TriggerKey

/// A modifier, optionally side-specific.
///
/// **The raw values are persisted.** `Defaults[.triggerKeys]` stores integers, so a user with
/// right Option currently has `[5]` on disk. Reordering these cases silently rebinds every
/// existing user's hotkey to a different modifier, which is close to unfixable after the fact
/// because there is no way to tell an old value from a new one. The order below matches what
/// Lowtech declared and must not change; new cases go on the end.
enum TriggerKey: Int, Codable, CaseIterable, Identifiable, Comparable, Defaults.Serializable {
    case lshift = 0
    case lctrl = 1
    case lalt = 2
    case lcmd = 3
    case rcmd = 4
    case ralt = 5
    case rctrl = 6
    case rshift = 7
    case cmd = 8
    case alt = 9
    case ctrl = 10
    case shift = 11
    case fn = 12
    case capsLock = 13

    var id: Int { rawValue }

    /// The symbol shown in the picker.
    var str: String {
        switch self {
        case .lcmd, .rcmd, .cmd: "⌘"
        case .lalt, .ralt, .alt: "⌥"
        case .lctrl, .rctrl, .ctrl: "⌃"
        case .lshift, .rshift, .shift: "⇧"
        case .fn: "fn"
        case .capsLock: "⇪"
        }
    }

    /// Spelled out, for the sentence under the picker. Eight near-identical glyphs are
    /// impossible to tell apart at a glance, which is how a four-modifier chord gets set by
    /// accident.
    var readableStr: String {
        switch self {
        case .lcmd: "Left Command"
        case .rcmd: "Right Command"
        case .cmd: "Command"
        case .lalt: "Left Option"
        case .ralt: "Right Option"
        case .alt: "Option"
        case .lctrl: "Left Control"
        case .rctrl: "Right Control"
        case .ctrl: "Control"
        case .lshift: "Left Shift"
        case .rshift: "Right Shift"
        case .shift: "Shift"
        case .fn: "Fn"
        case .capsLock: "Caps Lock"
        }
    }

    /// Abbreviated name: side plus modifier, e.g. "R⌘".
    var shortReadableStr: String {
        switch self {
        case .lcmd, .lalt, .lctrl, .lshift: "L" + str
        case .rcmd, .ralt, .rctrl, .rshift: "R" + str
        default: str
        }
    }

    /// Carbon registers hotkeys without distinguishing left from right, so a side-specific
    /// trigger collapses to its plain modifier here. This is what upstream did too: choosing
    /// "Right Command" registers Command, and the left key fires the hotkey as well.
    var sideIndependentModifier: NSEvent.ModifierFlags {
        switch self {
        case .lcmd, .rcmd, .cmd: .command
        case .lalt, .ralt, .alt: .option
        case .lctrl, .rctrl, .ctrl: .control
        case .lshift, .rshift, .shift: .shift
        case .fn: .function
        case .capsLock: .capsLock
        }
    }

    static func < (lhs: TriggerKey, rhs: TriggerKey) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension [TriggerKey] {
    var sideIndependentModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(map(\.sideIndependentModifier))
    }

    var str: String { map(\.str).joined() }
    var readableStr: String { map(\.readableStr).joined(separator: " + ") }

    /// Compact spelled-out form for the menu bar, where "Right Command + Right Option" does not
    /// fit but the bare glyphs are ambiguous.
    var shortReadableStr: String { map(\.shortReadableStr).joined(separator: "+") }
}

// MARK: - SauceKey

extension SauceKey: Defaults.Serializable {}

extension SauceKey {
    /// What to draw on the key cap.
    ///
    /// Goes through Sauce so the label follows the user's actual keyboard layout: the physical
    /// key that types `/` on QWERTY types something else on AZERTY, and showing the QWERTY
    /// legend there would be wrong. Return and Space get glyphs because their names are too
    /// long for a key cap.
    var character: String {
        switch QWERTYKeyCode.i {
        case kVK_Return: return "⏎"
        case kVK_Space: return "⎵"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_Tab: return "⇥"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            let char = Sauce.shared.character(for: QWERTYKeyCode.i, cocoaModifiers: [])?.uppercased()
                ?? rawValue.uppercased()
            // Sauce spells the digits out for some layouts; the key cap wants the digit.
            let spelled = ["ZERO": "0", "ONE": "1", "TWO": "2", "THREE": "3", "FOUR": "4",
                           "FIVE": "5", "SIX": "6", "SEVEN": "7", "EIGHT": "8", "NINE": "9"]
            return spelled[char] ?? char
        }
    }

    /// Lowercase form of the key cap label, for building shortcut strings.
    var lowercasedChar: String { character.lowercased() }

    /// Every key a hotkey may bind to.
    ///
    /// Sauce's `Key` is not `CaseIterable`, so this walks the virtual key-code space instead.
    /// 0...127 covers every key a Mac keyboard can report; codes with no `Key` are simply
    /// absent. Modifiers never appear here because Sauce does not model them as keys, which is
    /// correct: a modifier is the trigger, not the bound key.
    static let ALL_KEYS: Set<SauceKey> = Set((0 ... 127).compactMap { SauceKey(QWERTYKeyCode: $0) })

    /// Letters and digits only, for bindings that must stay typeable.
    static let ALPHANUMERIC_KEYS: Set<SauceKey> = Set(
        "abcdefghijklmnopqrstuvwxyz0123456789".compactMap { SauceKey(rawValue: String($0)) }
    )
}

extension Set<SauceKey> {
    static var ALL_KEYS: Set<SauceKey> { SauceKey.ALL_KEYS }
    static var ALPHANUMERIC_KEYS: Set<SauceKey> { SauceKey.ALPHANUMERIC_KEYS }
}

// MARK: - KeysManager

/// Owns the single global summon hotkey.
///
/// Narrower than Lowtech's, which juggled primary/secondary/alt/shift hotkey banks. Snag binds
/// exactly one, so this holds one.
private let hotkeyLog = Logger(subsystem: snagSubsystem, category: "Hotkey")

@MainActor
final class KeysManager: ObservableObject {
    static let shared = KeysManager()

    /// The key half of the combination. Nil disables the hotkey entirely.
    var specialKey: SauceKey? { didSet { guard specialKey != oldValue else { return }; reinitHotkeys() } }

    /// The modifier half. An empty list disables the hotkey: a bare key with no modifier would
    /// swallow that keystroke system-wide.
    var specialKeyModifiers: [TriggerKey] = [] { didSet { guard specialKeyModifiers != oldValue else { return }; reinitHotkeys() } }

    var onSpecialHotkey: (() -> Void)?

    // Live modifier state, published so the toolbar can swap in alternate actions while a
    // modifier is held. Side-specific here, unlike the hotkey itself: Carbon cannot register a
    // side-specific hotkey, but NSEvent does report which physical key is down, and the
    // alternate-action UI wants that distinction.
    @Published private(set) var lcmd = false
    @Published private(set) var rcmd = false
    @Published private(set) var lalt = false
    @Published private(set) var ralt = false
    @Published private(set) var lctrl = false
    @Published private(set) var rctrl = false

    /// Start watching modifier keys. Local only, so no Accessibility permission is needed: the
    /// alternate actions are in Snag's own window, and there is nothing to show while another
    /// app is focused.
    func startFlagsMonitor() {
        guard flagsMonitor == nil, !SWIFTUI_PREVIEW else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateFlags(event)
            return event
        }
    }

    /// `NSEvent.modifierFlags` only says "Option is down", not which one. The device-dependent
    /// bits carry the side, and they are the only way to tell left from right.
    private func updateFlags(_ event: NSEvent) {
        let raw = event.modifierFlags.rawValue
        lcmd = raw & UInt(NX_DEVICELCMDKEYMASK) != 0
        rcmd = raw & UInt(NX_DEVICERCMDKEYMASK) != 0
        lalt = raw & UInt(NX_DEVICELALTKEYMASK) != 0
        ralt = raw & UInt(NX_DEVICERALTKEYMASK) != 0
        lctrl = raw & UInt(NX_DEVICELCTLKEYMASK) != 0
        rctrl = raw & UInt(NX_DEVICERCTLKEYMASK) != 0
    }

    private var flagsMonitor: Any?

    /// Tear down and re-register. Cheap, and called on every relevant preference change.
    func reinitHotkeys() {
        unregister()
        guard !SWIFTUI_PREVIEW else { return }
        guard let specialKey, !specialKeyModifiers.isEmpty else {
            hotkeyLog.info("not registering: key=\(String(describing: self.specialKey), privacy: .public) modifiers=\(self.specialKeyModifiers.count, privacy: .public)")
            return
        }
        guard let combo = KeyCombo(key: specialKey, cocoaModifiers: specialKeyModifiers.sideIndependentModifiers) else {
            hotkeyLog.error("KeyCombo rejected key=\(specialKey.rawValue, privacy: .public)")
            return
        }

        // Closure form, not target/action. Magnet invokes a target via
        // `target.perform(selector, with:)`, which is an NSObject method; KeysManager is a plain
        // Swift class, so the registration succeeded and the callback silently went nowhere.
        // That is exactly the failure this had: `register -> true` in the log, nothing on press.
        let hotkey = HotKey(
            identifier: Self.identifier,
            keyCombo: combo,
            actionQueue: .main
        ) { [weak self] _ in
            self?.onSpecialHotkey?()
        }
        let ok = hotkey.register()
        hotkeyLog.info("register key=\(specialKey.rawValue, privacy: .public) mods=\(self.specialKeyModifiers.map(\.readableStr).joined(separator: "+"), privacy: .public) -> \(ok, privacy: .public)")
        registered = hotkey
    }

    private static let identifier = "snag-summon"
    private var registered: HotKey?

    private func unregister() {
        registered?.unregister()
        registered = nil
    }

}

@MainActor let KM = KeysManager.shared
