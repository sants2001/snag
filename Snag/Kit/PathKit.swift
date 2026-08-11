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

    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
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

    // The `/` path-join operator is deliberately NOT defined yet. Unqualified *name* lookup
    // prefers the current module, which is why every other member here silently takes over from
    // Lowtech's version with no call-site edits. Operator lookup has no such rule: it gathers
    // every visible candidate and reports "ambiguous use of operator '/'" while both modules
    // define one. It gets added in the same commit that drops Lowtech from the project.
}

// MARK: - URL

extension URL {
    var filePath: FilePath? {
        isFileURL ? FilePath(path) : nil
    }
}

// MARK: - Collections

extension Collection {
    var isNotEmpty: Bool { !isEmpty }
}

extension SetAlgebra {
    var isNotEmpty: Bool { !isEmpty }
}

extension Sequence where Element: Hashable {
    var set: Set<Element> { Set(self) }
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
