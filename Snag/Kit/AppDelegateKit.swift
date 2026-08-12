//
//  The app delegate base class, replacing Lowtech's.
//
//  Lowtech layered LowtechAppDelegate (NSObject + NSApplicationDelegate + a Combine bag) and
//  LowtechIndieAppDelegate (which added a Sparkle updater controller). Snag's own AppDelegate
//  subclassed the latter. Both collapse into this one class, carrying only what Snag calls.
//

import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
class SnagAppDelegate: NSObject, NSApplicationDelegate, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    /// Combine subscriptions that live as long as the app. Preference observers go here.
    var observers = Set<AnyCancellable>()

    /// Set once the delegate has finished launching. Guards work that assumes a built UI.
    var initialized = false

    /// `applicationDidBecomeActive` fires once during launch, before any window exists. Snag
    /// uses this to ignore that first one and only react to genuine re-activation.
    var didBecomeActiveAtLeastOnce = false

    /// Sparkle's controller. Constructed with `startingUpdater: false`: Snag ships no appcast
    /// (`SUFeedURL` is deliberately absent so Sparkle cannot pull upstream's gated release), so
    /// starting it would only schedule checks that can never resolve.
    lazy var updateController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: self
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        initialized = true
    }

    func applicationDidBecomeActive(_ notification: Notification) {}
    func applicationDidResignActive(_ notification: Notification) {}
}

/// Sparkle release channels. Snag publishes none, so this is empty rather than absent: the
/// delegate protocol wants an answer and "no channels" is the honest one.
func lowtechAllowedChannels() -> Set<String> { [] }

// MARK: - Drag-and-drop path fidelity

/// Make dragged files report their real path rather than a temporary copy.
///
/// AppKit answers a drag by copying the file into a temporary directory and handing over that
/// path, so a receiving app sees `/var/folders/...` instead of the file the user actually
/// dragged. Snag's whole purpose is producing the real path, so it swaps the copy for a symlink
/// and resolves symlinks on the way into the pasteboard.
///
/// This is method swizzling, which is worth being uncomfortable about: it changes `FileManager`
/// behaviour process-wide, not just for drags. The narrower alternative is a custom
/// `NSFilePromiseProvider`, which is the correct fix and a much larger change.
func swizzleDraggableToRealPath() {
    if let original = class_getInstanceMethod(FileManager.self, NSSelectorFromString("copyItemAtURL:toURL:error:")),
       let replacement = class_getInstanceMethod(FileManager.self, #selector(FileManager.snag_copyItem(at:to:error:)))
    {
        method_exchangeImplementations(original, replacement)
    }
    if let original = class_getInstanceMethod(NSPasteboardItem.self, #selector(NSPasteboardItem.setString(_:forType:))),
       let replacement = class_getInstanceMethod(NSPasteboardItem.self, #selector(NSPasteboardItem.snag_setString(_:forType:)))
    {
        method_exchangeImplementations(original, replacement)
    }
}

extension FileManager {
    /// Symlink instead of copying. After swizzling, `snag_copyItem` *is* the original
    /// implementation, so the recursive-looking call below performs the real copy.
    ///
    /// The `error` pointer is passed straight through rather than being written to: on the
    /// symlink path there is nothing to report, and on the fallback path the original
    /// implementation fills it in.
    @objc func snag_copyItem(at src: URL, to dst: URL, error: NSErrorPointer) -> Bool {
        if (try? createSymbolicLink(at: dst, withDestinationURL: src)) != nil {
            return true
        }
        return snag_copyItem(at: src, to: dst, error: error)
    }
}

extension NSPasteboardItem {
    /// Resolve symlinks on file-path strings so the receiver gets the real location rather than
    /// the link created above.
    @objc func snag_setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        guard type == .fileURL, let url = URL(string: string), url.isFileURL else {
            return snag_setString(string, forType: type)
        }
        let resolved = url.resolvingSymlinksInPath()
        return snag_setString(resolved.absoluteString, forType: type)
    }
}

// MARK: - Small conveniences

extension Bundle {
    /// Marketing version, e.g. "2.6.10".
    var version: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

extension String {
    var i32: Int32? { Int32(self) }

    /// Safe to use as a filename: path separators and the characters that confuse shells and
    /// Finder are replaced. Used for cache filenames derived from user or volume names.
    var safeFilename: String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\t\0")
        return components(separatedBy: illegal).joined(separator: "-")
    }
}

extension Data {
    /// UTF-8 decode, lossy enough to survive command output that is not quite valid.
    var s: String? { String(data: self, encoding: .utf8) }
}
