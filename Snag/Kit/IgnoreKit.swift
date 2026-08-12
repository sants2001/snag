//
//  Gitignore matching, replacing alin23/swift-ignore.
//
//  That package wraps a prebuilt Rust binary and ships with no licence file, making it the last
//  all-rights-reserved dependency and the only thing still blocking a distributable binary.
//  There is no wrapper to swap to, so the matching is implemented here.
//
//  Semantics follow gitignore(5), which Snag's `.fsignore` files use verbatim:
//
//    - blank lines and `#` comments are skipped; `\#` escapes a leading hash
//    - `!` negates, re-including something an earlier rule excluded
//    - a trailing `/` matches directories only
//    - a `/` anywhere except the end anchors the pattern to the ignore file's directory;
//      otherwise it matches at any depth
//    - `*` matches within a path segment, `**` spans segments, `?` matches one character,
//      `[abc]` and `[a-z]` are character classes
//    - **the last matching rule wins**, which is why the loop below cannot early-exit
//

import Foundation
import System

// MARK: - IgnoreRule

private struct IgnoreRule {
    let negated: Bool
    let directoryOnly: Bool
    /// Matches the named thing itself.
    let exact: NSRegularExpression
    /// Matches anything strictly beneath it.
    let under: NSRegularExpression

    /// Two regexes rather than one, because `build/` has to behave in two different ways at
    /// once: it matches the *directory* `build` only when the candidate is a directory, but it
    /// also excludes every *file* beneath it, and those files are not directories. A single
    /// pattern plus a "directories only" guard gets the second case wrong and silently indexes
    /// everything inside every ignored folder.
    func matches(_ relativePath: String, isDirectory: Bool) -> Bool {
        let range = NSRange(relativePath.startIndex ..< relativePath.endIndex, in: relativePath)
        if under.firstMatch(in: relativePath, options: [], range: range) != nil { return true }
        guard exact.firstMatch(in: relativePath, options: [], range: range) != nil else { return false }
        return !directoryOnly || isDirectory
    }
}

// MARK: - IgnoreFile

/// A parsed set of rules, matched against paths relative to a root.
private struct IgnoreFile {
    init(content: String) {
        rules = content
            .components(separatedBy: .newlines)
            .compactMap(IgnoreFile.parse)
        // A file with no negations can stop at the first match, which is the common case and
        // meaningfully cheaper across millions of paths.
        hasNegations = rules.contains { $0.negated }
    }

    let rules: [IgnoreRule]
    let hasNegations: Bool

    func isIgnored(_ relativePath: String, isDirectory: Bool) -> Bool {
        var ignored = false
        for rule in rules where rule.matches(relativePath, isDirectory: isDirectory) {
            // Last match wins, so this keeps going rather than returning early. Only safe to
            // break when nothing later could flip the answer back.
            ignored = !rule.negated
            if ignored, !hasNegations { return true }
        }
        return ignored
    }

    private static func parse(_ rawLine: String) -> IgnoreRule? {
        var line = rawLine

        // Trailing whitespace is insignificant unless backslash-escaped.
        while line.hasSuffix(" "), !line.hasSuffix("\\ ") {
            line.removeLast()
        }
        guard !line.isEmpty else { return nil }
        // `#:group ...` headers in Snag's shipped .fsignore are comments too.
        if line.hasPrefix("#") { return nil }
        if line.hasPrefix("\\#") { line.removeFirst() }

        var negated = false
        if line.hasPrefix("!") {
            negated = true
            line.removeFirst()
            guard !line.isEmpty else { return nil }
        }

        var directoryOnly = false
        if line.hasSuffix("/") {
            directoryOnly = true
            line.removeLast()
            guard !line.isEmpty else { return nil }
        }

        // A slash anywhere but the end anchors to the root. `foo/bar` matches only at the top;
        // plain `foo` matches at any depth.
        let anchored = line.dropLast(line.hasSuffix("/") ? 1 : 0).contains("/")
        if line.hasPrefix("/") { line.removeFirst() }

        let base = pattern(for: line, anchored: anchored)
        guard let exact = try? NSRegularExpression(pattern: base + "$"),
              let under = try? NSRegularExpression(pattern: base + "/.+$")
        else { return nil }
        return IgnoreRule(negated: negated, directoryOnly: directoryOnly, exact: exact, under: under)
    }

    /// Translate a glob into an anchored regex.
    private static func pattern(for glob: String, anchored: Bool) -> String {
        var out = anchored ? "^" : "^(?:.*/)?"
        var chars = Array(glob)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            switch c {
            case "*":
                if i + 1 < chars.count, chars[i + 1] == "*" {
                    // `**/` spans zero or more directories; a bare `**` spans anything.
                    if i + 2 < chars.count, chars[i + 2] == "/" {
                        out += "(?:.*/)?"
                        i += 3
                        continue
                    }
                    out += ".*"
                    i += 2
                    continue
                }
                // A single star stops at a separator.
                out += "[^/]*"
            case "?":
                out += "[^/]"
            case "[":
                // Character class passes through, with the negation form `[!abc]` rewritten to
                // regex's `[^abc]`.
                var cls = "["
                var j = i + 1
                if j < chars.count, chars[j] == "!" || chars[j] == "^" {
                    cls += "^"
                    j += 1
                }
                while j < chars.count, chars[j] != "]" {
                    if chars[j] == "\\", j + 1 < chars.count {
                        cls += "\\" + String(chars[j + 1])
                        j += 2
                        continue
                    }
                    cls += String(chars[j])
                    j += 1
                }
                if j < chars.count {
                    out += cls + "]"
                    i = j + 1
                    continue
                }
                // Unterminated class: treat the bracket as a literal.
                out += "\\["
            case "\\":
                if i + 1 < chars.count {
                    out += NSRegularExpression.escapedPattern(for: String(chars[i + 1]))
                    i += 2
                    continue
                }
                out += "\\\\"
            default:
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }

        // Left unterminated: the caller appends either `$` or `/.+$` to build the two forms.
        return out
    }
}

// MARK: - Cache

/// Parsed rule sets, keyed by their source.
///
/// Parsing compiles one `NSRegularExpression` per rule and the shipped `.fsignore` has well over
/// a hundred, while `isIgnored` is called once per indexed path. Without this the walk would
/// recompile the whole file millions of times.
private enum IgnoreCache {
    static func file(forContent content: String) -> IgnoreFile {
        lock.lock()
        defer { lock.unlock() }
        if let hit = byContent[content] { return hit }
        let parsed = IgnoreFile(content: content)
        byContent[content] = parsed
        return parsed
    }

    /// Load from a path, re-reading only when the file's modification time changes.
    static func file(atPath path: String) -> IgnoreFile? {
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date)??
            .timeIntervalSince1970 ?? 0

        lock.lock()
        if let hit = byPath[path], hit.stamp == stamp {
            lock.unlock()
            return hit.file
        }
        lock.unlock()

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let parsed = IgnoreFile(content: content)

        lock.lock()
        byPath[path] = (stamp, parsed)
        lock.unlock()
        return parsed
    }

    static func bust() {
        lock.lock()
        byContent.removeAll()
        byPath.removeAll()
        lock.unlock()
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var byContent: [String: IgnoreFile] = [:]
    nonisolated(unsafe) private static var byPath: [String: (stamp: TimeInterval, file: IgnoreFile)] = [:]
}

/// Drop every parsed ignore file. Called when rules are edited in Settings, and before a
/// reindex, since the walk caches per-directory `.gitignore` decisions.
///
/// Keeps the name the call sites already use.
func bust_gitignore_cache() {
    IgnoreCache.bust()
}

// MARK: - Public API

extension String {
    /// Whether this path is ignored by the rules in `ignoreFile`.
    ///
    /// `ignoreFile` is a *path* to an ignore file. Patterns are interpreted relative to that
    /// file's own directory, matching git.
    func isIgnored(in ignoreFile: String, bustCache: Bool = false) -> Bool {
        if bustCache { IgnoreCache.bust() }
        guard let rules = IgnoreCache.file(atPath: ignoreFile) else { return false }
        let root = (ignoreFile as NSString).deletingLastPathComponent
        return Self.check(self, rules: rules, root: root)
    }

    /// Match against rules anchored at `root` rather than the ignore file's own directory.
    ///
    /// Needed when the ignore file lives outside the tree it describes: Snag keeps per-scope
    /// rules in its cache directory while they describe `/Applications` or `/usr`.
    func isIgnored(in ignoreFile: String, root: String, bustCache: Bool = false) -> Bool {
        if bustCache { IgnoreCache.bust() }
        // `root:` callers sometimes pass rule text directly rather than a path.
        let rules = IgnoreCache.file(atPath: ignoreFile) ?? IgnoreCache.file(forContent: ignoreFile)
        return Self.check(self, rules: rules, root: root)
    }

    private static func check(_ path: String, rules: IgnoreFile, root: String) -> Bool {
        var relative = path
        if !root.isEmpty, root != "/", path.hasPrefix(root) {
            relative = String(path.dropFirst(root.count))
        } else if root == "/" {
            relative = path
        }
        while relative.hasPrefix("/") { relative.removeFirst() }
        guard !relative.isEmpty else { return false }

        // A trailing slash in the candidate is how callers signal a directory.
        let isDirectory = path.hasSuffix("/")
        if isDirectory { relative = String(relative.dropLast()) }

        return rules.isIgnored(relative, isDirectory: isDirectory)
    }
}

extension FilePath {
    func isIgnored(in ignoreFile: String, bustCache: Bool = false) -> Bool {
        string.isIgnored(in: ignoreFile, bustCache: bustCache)
    }

    func isIgnored(in ignoreFile: FilePath, bustCache: Bool = false) -> Bool {
        string.isIgnored(in: ignoreFile.string, bustCache: bustCache)
    }

    func isIgnored(in ignoreFile: String, root: String, bustCache: Bool = false) -> Bool {
        string.isIgnored(in: ignoreFile, root: root, bustCache: bustCache)
    }
}

// MARK: - Self-check

#if DEBUG
/// Run with `SNAG_IGNORE_SELFTEST=1`. Not a test target: this app has none, and a matcher that
/// silently mis-parses a rule would quietly drop files from the index or fill it with junk, so
/// the rules that matter get asserted somewhere.
func ignoreSelfTest() {
    let rules = """
    # comment
    .DS_Store
    build/
    *.log
    **/*.noindex
    !keep.log
    /rootonly
    docs/*.tmp
    """

    func ignored(_ path: String, dir: Bool = false) -> Bool {
        IgnoreCache.file(forContent: rules).isIgnored(path, isDirectory: dir)
    }

    assert(ignored(".DS_Store"), "bare name matches at root")
    assert(ignored("a/b/.DS_Store"), "bare name matches at any depth")
    assert(ignored("build", dir: true), "trailing slash matches a directory")
    assert(!ignored("build"), "trailing slash does not match a file")
    assert(ignored("build/x/y.txt"), "everything under an ignored directory is ignored")
    assert(ignored("x/y.log"), "star matches within a segment")
    assert(!ignored("keep.log"), "negation re-includes, and wins by coming later")
    assert(ignored("a/b/c.noindex"), "double star spans segments")
    assert(ignored("rootonly"), "leading slash anchors to the root")
    assert(!ignored("sub/rootonly"), "anchored rule does not match deeper")
    assert(ignored("docs/x.tmp"), "internal slash anchors the pattern")
    assert(!ignored("a/docs/x.tmp"), "anchored pattern does not match deeper")
    assert(!ignored("notes.txt"), "unmatched paths are not ignored")
    print("ignoreSelfTest: all assertions passed")
}
#endif
