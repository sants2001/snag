//
//  Locating the crash reports macOS already wrote.
//
//  Snag ships no crash reporter and sends nothing, which means a crash on someone else's Mac is
//  invisible unless they choose to report it. This does not change that: it only removes the
//  work of finding the log, so reporting is a click rather than a research project.
//
//  Nothing here reads, uploads or transmits a report. It reveals a file in Finder.
//

import AppKit
import Foundation

enum SnagCrashLogs {
    /// Where macOS writes per-user crash reports. `.ips` since Monterey; `.crash` before that,
    /// and both still turn up on machines upgraded in place.
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    /// Every crash report belonging to Snag, newest first.
    ///
    /// Matches on the process name prefix rather than the bundle id: the filename is
    /// `Snag-2026-08-12-140533.ips`, and the bundle id appears only inside the file.
    static var reports: [URL] {
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidates
            .filter { $0.lastPathComponent.hasPrefix("Snag-") }
            .filter { ["ips", "crash"].contains($0.pathExtension) }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    /// Whether to offer the button at all. Showing it unconditionally would imply Snag has been
    /// crashing, which for most users it has not.
    static var hasAny: Bool { !reports.isEmpty }

    /// Reveal the newest report in Finder, selected and ready to drag into a GitHub issue.
    static func revealLatest() {
        guard let latest = reports.first else {
            NSWorkspace.shared.open(directory)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([latest])
    }
}
