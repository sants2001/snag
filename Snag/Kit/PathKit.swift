//
//  Path, string and process conveniences that Snag used from Lowtech.
//
//  Lowtech has no licence file, which blocks distributing a compiled binary. See
//  docs/independence-plan.md. This is the pervasive half of that dependency: `FilePath` alone
//  appears in 28 files, so these extensions are load-bearing throughout the app rather than
//  confined to one layer.
//
//  Written to match the behaviour the app relies on, which in a couple of cases is more than
//  the obvious one-liner. Where that matters it is called out in a comment, because a silent
//  difference in path handling would be very hard to trace back here.
//

import AppKit
import Foundation
import System

private let fm = FileManager.default

/// Anchored, case-insensitive match on the home directory prefix, used to abbreviate paths for
/// display. Built once: `Regex` compilation is not free and this runs per row in list views.
private let homeDirRegex = (try? Regex("^/*?\(NSHomeDirectory())(/)?", as: (Substring, Substring?).self))?.ignoresCase()

// MARK: - String

extension String {
    /// Strip the punctuation that comes along when a path is pasted, dragged, or read out of a
    /// shell command: surrounding quotes, braces and commas, plus whitespace and newlines.
    ///
    /// Without this, a path dragged in from Terminal arrives wrapped in quotes and every
    /// subsequent `exists` check fails for no visible reason.
    var trimmedPath: String {
        trimmingCharacters(in: ["\"", "'", "\n", "\t", " ", "{", "}", ","])
    }

    /// Parse into a `FilePath`, expanding a leading `~`.
    ///
    /// The length guard is not cosmetic. These strings can come from dropped items, script
    /// output and the CLI, and `FilePath` will happily build a multi-megabyte path that then
    /// gets handed to the indexer.
    var filePath: FilePath? {
        guard !isEmpty, count <= 4096 else { return nil }
        return FilePath(trimmedPath.expandingTildeInPath)
    }

    /// A path shortened for display, with the home directory written as `~`.
    var shellString: String {
        guard let homeDirRegex else {
            // Regex failed to build (a home directory containing regex metacharacters would do
            // it); fall back to a literal prefix replacement rather than showing nothing.
            guard hasPrefix(NSHomeDirectory()) else { return self }
            return "~" + dropFirst(NSHomeDirectory().count)
        }
        return replacing(homeDirRegex, with: { "~" + ($0.1 ?? "") })
    }

    /// A file URL for this path, whether or not it exists.
    var fileURL: URL? {
        guard !isEmpty, count <= 4096 else { return nil }
        return URL(fileURLWithPath: trimmedPath.expandingTildeInPath)
    }

    /// A file URL for this path. `NSApplication.application(_:openFiles:)` delivers plain
    /// paths, and everything downstream works in URLs.
    var url: URL? {
        guard !isEmpty, count <= 4096 else { return nil }
        return URL(fileURLWithPath: trimmedPath.expandingTildeInPath)
    }

    /// Parse and confirm in one step, so callers can `guard let` a path they know is real.
    var existingFilePath: FilePath? {
        guard let path = filePath, path.exists else { return nil }
        return path
    }

    var expandingTildeInPath: String {
        ns.expandingTildeInPath
    }

    /// Whitespace and newlines stripped from both ends.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Bridge to `NSString`, for the path APIs Foundation never brought over to `String`
    /// (`lastPathComponent`, `deletingPathExtension`, and friends).
    var ns: NSString { self as NSString }
}

// MARK: - FilePath

extension FilePath {
    static let root = FilePath("/")
    static let applications = FilePath("/Applications")
    static let home = FilePath(NSHomeDirectory())

    var url: URL {
        URL(fileURLWithPath: string)
    }

    var exists: Bool {
        fm.fileExists(atPath: string)
    }

    var isDir: Bool {
        var isDirectory = ObjCBool(false)
        return fm.fileExists(atPath: string, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Display form, with `$HOME` abbreviated to `~`.
    var shellString: String {
        string.shellString
    }

    /// Swap the extension, keeping the directory and stem.
    func withExtension(_ ext: String) -> FilePath {
        guard let stem else { return self }
        return removingLastComponent().appending("\(stem).\(ext)")
    }

    /// Create the directory. Returns true if it exists afterwards, including when it already
    /// did, so callers can treat this as idempotent.
    @discardableResult
    func mkdir(withIntermediateDirectories: Bool = true, permissions: Int = 0o755) -> Bool {
        guard !exists else { return true }
        do {
            try fm.createDirectory(
                atPath: string,
                withIntermediateDirectories: withIntermediateDirectories,
                attributes: [.posixPermissions: permissions]
            )
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    func copy(to path: FilePath, force: Bool = false) throws -> FilePath {
        guard path != self else { return path }
        if force, path.exists {
            try fm.removeItem(atPath: path.string)
        }
        try fm.copyItem(atPath: string, toPath: path.string)
        return path
    }

    /// The containing directory.
    var dir: FilePath { removingLastComponent() }

    @discardableResult
    func move(to path: FilePath, force: Bool = false) throws -> FilePath {
        guard path != self else { return path }
        if force, path.exists {
            try fm.removeItem(atPath: path.string)
        }
        try fm.moveItem(atPath: string, toPath: path.string)
        return path
    }

    /// The last path component. `/` has none, so it reports "Root".
    var name: FilePath.Component { lastComponent ?? "Root" }

    /// Modification time as a Unix timestamp, falling back to creation time. Nil when the path
    /// does not exist. Seconds rather than a `Date` because every call site compares it against
    /// `timeIntervalSince1970`.
    var timestamp: TimeInterval? {
        guard let attrs = try? fm.attributesOfItem(atPath: string) else { return nil }
        let date = attrs[FileAttributeKey.modificationDate] as? Date
            ?? attrs[FileAttributeKey.creationDate] as? Date
        return date?.timeIntervalSince1970
    }

    /// Modification time as a `Date`. Separate from `timestamp`, which returns seconds; both
    /// forms have call sites and converting at each one reads worse.
    var modificationDate: Date? {
        guard let attrs = try? fm.attributesOfItem(atPath: string) else { return nil }
        return attrs[FileAttributeKey.modificationDate] as? Date
            ?? attrs[FileAttributeKey.creationDate] as? Date
    }

    /// Size in bytes. Nil for directories and anything unreadable; a directory's own size is
    /// meaningless here and computing the recursive size would be far too slow per row.
    func fileSize() -> Int? {
        guard let attrs = try? fm.attributesOfItem(atPath: string) else { return nil }
        return (attrs[FileAttributeKey.size] as? NSNumber)?.intValue
    }

    /// Join a path component. Reads better than `appending` in the deeply nested path
    /// expressions this app is full of.
    ///
    /// This could not exist while Lowtech was linked. Unqualified *name* lookup prefers the
    /// current module, which is how every other member here took over silently with no
    /// call-site edits, but operator lookup has no such rule: it gathers every visible
    /// candidate and reports an ambiguity.
    static func / (lhs: FilePath, rhs: String) -> FilePath {
        lhs.appending(rhs)
    }

    /// Overload for the component type, which some call sites pass instead of a String.
    static func / (lhs: FilePath, rhs: FilePath.Component) -> FilePath {
        lhs.appending(rhs.string)
    }
}

extension Sequence where Element: Hashable {
    /// Duplicates removed, first-seen order preserved. Order matters: these feed list views
    /// where reshuffling on each refresh would be visible. `Set` would not do.
    var uniqued: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - URL

extension URL {
    var filePath: FilePath? {
        isFileURL ? FilePath(path) : nil
    }

    /// The path, but only if something is actually there.
    var existingFilePath: FilePath? {
        guard isFileURL, fm.fileExists(atPath: path) else { return nil }
        return FilePath(path)
    }
}

// MARK: - Collections

extension Collection {
    var isNotEmpty: Bool { !isEmpty }

    /// Bounds-checked access. Used where an index comes from a keystroke or a stale selection
    /// and trapping would be a crash rather than a bug report.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Sequence {
    /// Sort ascending by a comparable property, without spelling out the closure.
    func sorted(by keyPath: KeyPath<Element, some Comparable>) -> [Element] {
        sorted { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }

    /// The element with the greatest value of a comparable property.
    func max(by keyPath: KeyPath<Element, some Comparable>) -> Element? {
        self.max { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }

    /// The element with the least value of a comparable property.
    func min(by keyPath: KeyPath<Element, some Comparable>) -> Element? {
        self.min { $0[keyPath: keyPath] < $1[keyPath: keyPath] }
    }
}

extension SetAlgebra {
    var isNotEmpty: Bool { !isEmpty }
}

extension Sequence where Element: Hashable {
    var set: Set<Element> { Set(self) }
}

extension Sequence where Element: Hashable {
    /// Everything except the given elements, order preserved.
    ///
    /// Takes the exclusions as a Set first: the callers pass a batch of removed paths and
    /// filtering with `contains` on an Array would be quadratic over result lists that run to
    /// thousands of entries.
    func without(_ excluded: some Sequence<Element>) -> [Element] {
        let drop = Set(excluded)
        return filter { !drop.contains($0) }
    }

    /// Single-element form, for removing one filter from a list.
    func without(_ excluded: Element) -> [Element] {
        filter { $0 != excluded }
    }
}

extension Sequence {
    /// Materialise into an Array. Mostly used on Sets, where the call sites need a stable
    /// ordered value to hand to SwiftUI.
    var arr: [Element] { Array(self) }
}

// MARK: - Dispatch

/// Run on the main thread, inline if already there.
///
/// Distinct from `mainActor` in SnagKit, which always defers. Several call sites here depend on
/// the work having happened by the time the call returns.
@inline(__always)
func mainAsync(_ action: @escaping () -> Void) {
    guard !Thread.isMainThread else {
        action()
        return
    }
    DispatchQueue.main.async(execute: action)
}

@discardableResult
func mainAsyncAfter(ms: Int, _ action: @escaping () -> Void) -> DispatchWorkItem {
    let item = DispatchWorkItem(block: action)
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: item)
    return item
}

@discardableResult
func mainAsyncAfter(_ seconds: TimeInterval, _ action: @escaping () -> Void) -> DispatchWorkItem {
    let item = DispatchWorkItem(block: action)
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    return item
}

// MARK: - Shell

extension Process {
    /// Where this process's output was redirected, recorded at launch by `shellProc` so a
    /// caller holding only the `Process` can still find the files afterwards.
    var stdoutFilePath: String? { environment?["__snag_stdout"] }
    var stderrFilePath: String? { environment?["__snag_stderr"] }
}

/// Launch a command with stdout and stderr redirected to files, without waiting for it.
///
/// Files rather than pipes on purpose: a pipe whose buffer fills blocks the child until someone
/// drains it, and these are launched from the main thread.
func shellProc(_ launchPath: String = "/bin/zsh", args: [String], env: [String: String]? = nil) -> Process? {
    let outDir = fm.temporaryDirectory.appendingPathComponent("snag-proc-\(UUID().uuidString)")
    guard (try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)) != nil else { return nil }

    let outPath = outDir.appendingPathComponent("stdout").path
    let errPath = outDir.appendingPathComponent("stderr").path
    fm.createFile(atPath: outPath, contents: nil)
    fm.createFile(atPath: errPath, contents: nil)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = args

    var environment = env ?? ProcessInfo.processInfo.environment
    environment["__snag_stdout"] = outPath
    environment["__snag_stderr"] = errPath
    process.environment = environment

    process.standardOutput = FileHandle(forWritingAtPath: outPath)
    process.standardError = FileHandle(forWritingAtPath: errPath)

    do {
        try process.run()
    } catch {
        return nil
    }
    return process
}

// MARK: - ShellResult

struct ShellResult {
    let output: String?
    let error: String?
    let exitCode: Int32

    var success: Bool { exitCode == 0 }

    /// Trimmed stdout and stderr. Short names because the call sites read `result.o` and reach
    /// for them constantly; command output almost always arrives with a trailing newline that
    /// every caller would otherwise strip by hand.
    var o: String? { output?.trimmingCharacters(in: .whitespacesAndNewlines) }
    var e: String? { error?.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Run a command to completion and collect its output.
///
/// Named `runShell` rather than `shell`. A free function with the same name in two visible
/// modules is ambiguous at the call site: unlike a type member, there is no rule preferring the
/// current module. Renaming is cheaper and clearer than fighting overload resolution, and there
/// are only three callers.
@discardableResult
func runShell(
    _ launchPath: String = "/bin/zsh",
    command: String? = nil,
    args: [String] = [],
    timeout: TimeInterval? = nil,
    env: [String: String]? = nil
) -> ShellResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = command.map { ["-c", $0] } ?? args
    if let env { process.environment = env }

    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err

    do {
        try process.run()
    } catch {
        return ShellResult(output: nil, error: error.localizedDescription, exitCode: -1)
    }

    // Drain before waiting. A child that fills the 64KB pipe buffer blocks forever if the
    // parent is sitting in waitUntilExit() instead of reading.
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()

    if let timeout {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning { process.terminate() }
    }
    process.waitUntilExit()

    return ShellResult(
        output: String(data: outData, encoding: .utf8),
        error: String(data: errData, encoding: .utf8),
        exitCode: process.terminationStatus
    )
}

// MARK: - Numeric conveniences

extension BinaryInteger {
    /// Widen to `Int`. Reads better than `Int(x)` when chained, which is why the call sites use
    /// it: `QWERTYKeyCode.i` rather than `Int(QWERTYKeyCode)`.
    var i: Int { Int(self) }

    /// Widen to `UInt32`, for the Core Foundation and Metadata APIs that take one.
    var u: UInt32 { UInt32(self) }

    /// String form. Used where a number becomes a key equivalent or a label.
    var s: String { String(self) }

    /// Widen to `Double`, for the arithmetic that needs fractions.
    var d: Double { Double(self) }
}

// MARK: - Floating point formatting

extension BinaryFloatingPoint {
    /// Fixed-decimal string, e.g. `1.5` for a file size. `String(format:)` rather than a
    /// NumberFormatter: this runs per visible row and a formatter allocation there is wasteful.
    func str(decimals: UInt8) -> String {
        String(format: "%.\(decimals)f", Double(self))
    }

    /// Rounded to the nearest whole number.
    var intround: Int { Int(Double(self).rounded()) }
}

// MARK: - Sequence to dictionary

extension Sequence {
    /// Build a dictionary by deriving a key/value pair from each element. Later collisions win,
    /// which is what the callers expect and what `Dictionary(uniqueKeysWith:)` would trap on.
    func dict<K: Hashable, V>(_ transform: (Element) -> (K, V)?) -> [K: V] {
        Dictionary(compactMap(transform), uniquingKeysWith: { _, last in last })
    }
}

// MARK: - NSRunningApplication

extension NSRunningApplication {
    /// Display name, preferring the localized bundle name over the process name.
    ///
    /// `localizedName` is nil for some background and helper processes, so the bundle's display
    /// name is the fallback rather than the other way round.
    var name: String? {
        localizedName
            ?? bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleDisplayName"] as? String }
            ?? bundleURL?.deletingPathExtension().lastPathComponent
    }
}
