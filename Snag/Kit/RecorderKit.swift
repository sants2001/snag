//
//  The hotkey recorder controls, replacing Lowtech's.
//
//  Two pieces: a key cap you click and then press a key on, and a row of modifier toggles.
//  Both appear on the first-run screen and in Settings > Keyboard Shortcuts.
//

import Carbon
import Defaults
import Sauce
import SwiftUI

// MARK: - DynamicKey

/// A key cap that records the next keypress when clicked.
///
/// While recording, `recording` is bound out so the rest of the app can suspend its own key
/// handling. Without that, pressing Escape to cancel would instead dismiss the window, and
/// Return would trigger the default button rather than binding.
struct DynamicKey: View {
    init(
        key: Binding<SauceKey>,
        recording: Binding<Bool>? = nil,
        allowedKeys: Set<SauceKey>? = nil,
        width: CGFloat? = nil
    ) {
        _key = key
        _recording = recording ?? .constant(false)
        self.allowedKeys = allowedKeys
        self.width = width
    }

    var body: some View {
        Button(action: { recording.toggle() }) {
            Text(recording ? "•••" : key.character)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(minWidth: width ?? 26, minHeight: 22)
                .padding(.horizontal, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(recording ? Color.red.opacity(0.85) : Color.primary.opacity(hovering ? 0.16 : 0.09))
                )
                .foregroundStyle(recording ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(recording ? "Press a key, or Escape to cancel" : "Click to change")
        .background(KeyRecorder(recording: $recording, allowedKeys: allowedKeys) { key = $0 })
        .animation(.easeOut(duration: 0.12), value: recording)
    }

    @Binding private var key: SauceKey
    @Binding private var recording: Bool
    @State private var hovering = false

    private let allowedKeys: Set<SauceKey>?
    private let width: CGFloat?
}

// MARK: - KeyRecorder

/// Captures the next keypress while `recording` is true.
///
/// A local monitor rather than a global one: this only needs keys aimed at Snag's own window,
/// and a global monitor would require Accessibility permission just to change a setting.
/// Returning nil from the handler swallows the event so the keystroke does not also reach the
/// app underneath.
private struct KeyRecorder: NSViewRepresentable {
    @Binding var recording: Bool
    let allowedKeys: Set<SauceKey>?
    let onKey: (SauceKey) -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onKey = onKey
        context.coordinator.allowedKeys = allowedKeys
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onKey = onKey
        context.coordinator.allowedKeys = allowedKeys
        context.coordinator.setRecording(recording) { recording = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onKey: ((SauceKey) -> Void)?
        var allowedKeys: Set<SauceKey>?

        deinit {
            // deinit is nonisolated; the monitor must come off on the main actor.
            if let monitor { MainActor.assumeIsolated { NSEvent.removeMonitor(monitor) } }
        }

        @MainActor
        func setRecording(_ on: Bool, update: @escaping (Bool) -> Void) {
            guard on != (monitor != nil) else { return }
            if on {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    defer { update(false) }

                    // Escape cancels without binding, which is why Escape itself cannot be
                    // bound through this control.
                    if event.keyCode == UInt16(kVK_Escape) { return nil }

                    guard let key = SauceKey(QWERTYKeyCode: Int(event.keyCode)),
                          allowedKeys?.contains(key) ?? true
                    else {
                        // Rejected keys are swallowed too. Letting them through would type the
                        // character into whatever field is behind the recorder.
                        return nil
                    }
                    onKey?(key)
                    return nil
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        @MainActor private var monitor: Any?
    }
}

// MARK: - DirectionalModifierView

/// The modifier picker: left-hand modifiers, a gap, then right-hand ones.
///
/// Laid out physically, mirroring a keyboard, so "Right Command" is the glyph on the right.
/// Selecting from both sides is allowed because a chord is legal, though rarely what anyone
/// wants.
struct DirectionalModifierView: View {
    @Binding var triggerKeys: [TriggerKey]
    var showFnCaps = true

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.left) { modifierButton($0) }
            Spacer().frame(width: 10)
            ForEach(Self.right) { modifierButton($0) }
            if showFnCaps {
                Spacer().frame(width: 10)
                ForEach(Self.extras) { modifierButton($0) }
            }
        }
    }

    // Ordered as they sit on the keyboard, outside in.
    private static let left: [TriggerKey] = [.lshift, .lctrl, .lalt, .lcmd]
    private static let right: [TriggerKey] = [.rcmd, .ralt, .rctrl, .rshift]
    private static let extras: [TriggerKey] = [.fn, .capsLock]

    @ViewBuilder
    private func modifierButton(_ key: TriggerKey) -> some View {
        let selected = triggerKeys.contains(key)
        Button(action: { toggle(key) }) {
            Text(key.str)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.primary.opacity(0.09))
                )
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key.readableStr)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private func toggle(_ key: TriggerKey) {
        if let index = triggerKeys.firstIndex(of: key) {
            triggerKeys.remove(at: index)
        } else {
            // Kept sorted so the stored array is stable regardless of click order; otherwise
            // two users with the same chord would have different values on disk.
            triggerKeys = (triggerKeys + [key]).sorted()
        }
    }
}
