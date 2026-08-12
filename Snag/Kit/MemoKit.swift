//
//  Per-value memoization, replacing Lowtech's `memoz`.
//
//  Written rather than pulling in MemoZ (which is MIT and would have been fine) because the
//  whole surface Snag uses is `value.memoz.someProperty`, and that is a small amount of code
//  next to another package in the graph.
//
//  Why it exists at all: the results list computes size, modification date, icon and volume for
//  every visible row, each of which is a `stat` or a Launch Services call. Recomputing them on
//  every SwiftUI body evaluation made scrolling stutter, and the row heights are measured before
//  display, so each value gets asked for more than once per frame.
//

import Foundation

// MARK: - MemoCache

/// Process-wide cache keyed by (value, property).
///
/// `NSCache` rather than a dictionary: it evicts under memory pressure on its own, which
/// matters because Snag indexes millions of paths and a plain dictionary here would grow without
/// any bound.
private enum MemoCache {
    static func value<Root: Hashable, Value>(
        for root: Root,
        _ keyPath: KeyPath<Root, Value>,
        compute: () -> Value
    ) -> Value {
        let key = Key(root: AnyHashable(root), keyPath: keyPath)
        lock.lock()
        if let boxed = cache.object(forKey: key), let hit = boxed.value as? Value {
            lock.unlock()
            return hit
        }
        lock.unlock()

        // Computed outside the lock: these are filesystem and Launch Services calls, and holding
        // a global lock across them would serialise every row in the list.
        let fresh = compute()

        lock.lock()
        cache.setObject(Box(fresh), forKey: key)
        lock.unlock()
        return fresh
    }

    /// Insert a known value without computing it.
    static func store<Root: Hashable, Value>(_ value: Value, for root: Root, _ keyPath: KeyPath<Root, Value>) {
        let key = Key(root: AnyHashable(root), keyPath: keyPath)
        lock.lock()
        cache.setObject(Box(value), forKey: key)
        lock.unlock()
    }

    /// Drop everything. Called when the index is rebuilt, since file metadata may have changed
    /// underneath entries that are still cached.
    static func clear() {
        lock.lock()
        cache.removeAllObjects()
        lock.unlock()
    }

    private static let cache: NSCache<Key, Box> = {
        let c = NSCache<Key, Box>()
        c.countLimit = 20_000
        return c
    }()
    private static let lock = NSLock()

    /// NSCache needs class keys, so the (value, keyPath) pair is boxed.
    private final class Key: NSObject {
        init(root: AnyHashable, keyPath: AnyKeyPath) {
            self.root = root
            self.keyPath = keyPath
        }

        let root: AnyHashable
        let keyPath: AnyKeyPath

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(root)
            hasher.combine(keyPath)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return root == other.root && keyPath == other.keyPath
        }
    }

    private final class Box {
        init(_ value: Any) { self.value = value }
        let value: Any
    }
}

// MARK: - Memoized

/// `value.memoz.property` returns `value.property`, computed once per distinct value.
///
/// `@dynamicMemberLookup` is what lets this stay transparent at the call site: adding a new
/// cached property means adding a normal computed property to the underlying type, with no
/// change here.
@dynamicMemberLookup
struct Memoized<Root: Hashable> {
    let root: Root

    subscript<Value>(dynamicMember keyPath: KeyPath<Root, Value>) -> Value {
        MemoCache.value(for: root, keyPath) { root[keyPath: keyPath] }
    }
}

extension Hashable {
    /// Seed the cache directly, for values already known from a cheaper source.
    ///
    /// The index knows whether each result is a directory, so pre-seeding `isDir` means the row
    /// never has to `stat` for something already in memory. This is the difference between a
    /// list that scrolls and one that hitches on every new row.
    func cache<Value>(_ value: Value, forKey keyPath: KeyPath<Self, Value>) {
        MemoCache.store(value, for: self, keyPath)
    }

    /// Memoized view of this value. Only sound for properties that are pure with respect to the
    /// value; anything reflecting mutable filesystem state goes stale until `clearMemoCache()`.
    var memoz: Memoized<Self> { Memoized(root: self) }
}

/// Drop every memoized value. Call after reindexing, when file metadata may have moved on.
func clearMemoCache() {
    MemoCache.clear()
}
