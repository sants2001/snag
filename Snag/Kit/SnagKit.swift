//
//  Replacements for the small helpers Snag used from Lowtech.
//
//  Lowtech ships with no licence file and is therefore all-rights-reserved, which blocks
//  distributing a compiled Snag binary. See docs/independence-plan.md. These are written
//  against the call sites in this app rather than ported, and the surface is deliberately
//  narrower than Lowtech's: only what Snag actually calls.
//

import AppKit
import Combine
import Defaults
import Foundation
import Sparkle
import SwiftUI

/// True when running inside an Xcode SwiftUI preview, where side effects like terminating a
/// sibling instance or registering global hotkeys are unwanted.
let SWIFTUI_PREVIEW = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

/// Hop to the main actor. Already-on-main callers still go through a `Task`, matching the
/// previous behaviour: several call sites rely on the work being deferred past the current
/// turn of the run loop, not run inline.
func mainActor(_ action: @escaping @MainActor () -> Void) {
    Task { @MainActor in action() }
}

/// Run work off the main thread, right now. The returned item is discarded at every call site
/// in this app; it is kept so `asyncNow` can be cancelled if that ever changes.
@discardableResult
func asyncNow(_ action: @escaping () -> Void) -> DispatchWorkItem {
    let item = DispatchWorkItem(block: action)
    DispatchQueue.global(qos: .userInitiated).async(execute: item)
    return item
}

/// Bring Snag to the front, over whatever app currently owns the keyboard.
func focus() {
    NSApp.activate(ignoringOtherApps: true)
}

/// Publisher for a Defaults key change, so callers can `.sink { $0.newValue }`.
func pub<Value: Defaults.Serializable>(_ key: Defaults.Key<Value>) -> AnyPublisher<(oldValue: Value, newValue: Value), Never> {
    Defaults.publisher(key)
        .map { (oldValue: $0.oldValue, newValue: $0.newValue) }
        .eraseToAnyPublisher()
}

// MARK: - Repeater

/// A repeating timer that survives being stored in a property and stops when released.
///
/// Snag uses this for polling that has no completion event to hang off: waiting for the user to
/// grant Full Disk Access in System Settings, and the hourly index freshness check. `tolerance`
/// matters for the latter; an hourly timer with no slack wakes the CPU on a hard schedule and
/// defeats coalescing.
final class Repeater {
    init(
        every interval: TimeInterval,
        name: String? = nil,
        tolerance: TimeInterval? = nil,
        action: @escaping () -> Void
    ) {
        self.name = name
        let timer = Timer(timeInterval: interval, repeats: true) { _ in action() }
        if let tolerance {
            timer.tolerance = tolerance
        }
        // .common so the timer keeps firing while a menu is open or a window is being dragged,
        // which is exactly when the Full Disk Access poll needs to notice a change.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    let name: String?

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private var timer: Timer?
}

// MARK: - EnvState

/// Shared UI state that has to be reachable from anywhere in the view tree.
///
/// Only `recording` is used: it suppresses the app's own key handling while a hotkey recorder
/// has focus, so pressing Escape or Return binds the key instead of dismissing the window.
final class EnvState: ObservableObject {
    @Published var recording = false
}

// `envState`, the shared instance, stays declared in SettingsView.swift where it was.

// MARK: - UpdateManager

/// Holds the Sparkle updater so views can reach it without touching the app delegate.
///
/// Snag has no appcast: `SUFeedURL` is deliberately absent from Info.plist so Sparkle cannot
/// replace a local build with upstream's signed, Pro-gated release. The updater is retained
/// only because `LowtechIndieAppDelegate` constructs one; nothing currently checks for updates.
@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var updater: SPUUpdater?
}

@MainActor let UM = UpdateManager.shared
