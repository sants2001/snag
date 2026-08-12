//
//  Spotlight metadata queries, replacing Lowtech's `MetaQuery`.
//
//  Snag uses this to discover installed applications for the "Open With" list, so the result set
//  is a few hundred app bundles and the query stays live to catch installs and moves.
//

import Combine
import Foundation
import System

// MARK: - MetaQuery

/// A running `NSMetadataQuery` with its notification plumbing attached.
///
/// The caller must hold on to the value: releasing it tears down the subscription and, for a
/// live query, stops the updates.
struct MetaQuery {
    /// - Parameters:
    ///   - live: keep running and re-invoke `handler` whenever Spotlight sees a matching item
    ///     appear, move or disappear. False stops after the first gather.
    ///   - valueListAttributes: prefetched during the gather phase. This is not an optimisation
    ///     to skip: without it, reading attributes later does a synchronous XPC round trip to
    ///     the metadata server *per item*, and doing that for several hundred app bundles on
    ///     the notifying run loop stalls the app for tens of seconds.
    ///   - handlerQueue: where `handler` runs. Pass one when the handler does per-item work, for
    ///     the same reason. Nil runs it on the notifying run loop.
    init(
        scopes: [String],
        queryString: String,
        live: Bool = false,
        valueListAttributes: [String] = [],
        handlerQueue: DispatchQueue? = nil,
        handler: @escaping ([NSMetadataItem]) -> Void
    ) {
        let q = NSMetadataQuery()
        q.searchScopes = scopes
        q.predicate = NSPredicate(fromMetadataQueryString: queryString)
        if !valueListAttributes.isEmpty {
            // Must be set before start().
            q.valueListAttributes = valueListAttributes
        }
        q.start()
        query = q

        observer = NotificationCenter.default
            .publisher(for: .NSMetadataQueryDidFinishGathering, object: q)
            .merge(with: NotificationCenter.default.publisher(for: .NSMetadataQueryDidUpdate, object: q))
            .sink { notification in
                guard let query = notification.object as? NSMetadataQuery, query == q else { return }

                // Freeze the results proxy while copying out of it. Live queries mutate it in
                // place, and enumerating during a mutation is a crash.
                q.disableUpdates()
                let items = query.results.compactMap { $0 as? NSMetadataItem }

                if let handlerQueue {
                    // Updates stay disabled across the off-thread handler so the snapshot it is
                    // reading cannot change underneath it, then re-enabled back on the main run
                    // loop once it is done.
                    handlerQueue.async {
                        handler(items)
                        DispatchQueue.main.async {
                            if live { q.enableUpdates() } else { q.stop() }
                        }
                    }
                } else {
                    if live { q.enableUpdates() } else { q.stop() }
                    handler(items)
                }
            }
    }

    let query: NSMetadataQuery
    let observer: any Cancellable
}

// MARK: - InstalledApp

struct InstalledApp {
    init(path: FilePath, name: String, useCount: Int, bundleIdentifier: String) {
        self.path = path
        self.name = name
        self.useCount = useCount
        self.bundleIdentifier = bundleIdentifier
    }

    let path: FilePath
    let name: String
    /// Spotlight's launch count, used to rank the "Open With" list so the apps someone actually
    /// uses come first.
    let useCount: Int
    let bundleIdentifier: String

    var url: URL { path.url }
}

// MARK: - App discovery

/// Where applications live. Watched for changes so the "Open With" list notices installs and
/// removals without waiting for Spotlight.
let APP_DIRS = ["/Applications", "/System/Applications", "\(NSHomeDirectory())/Applications"]

private let installedAppsQueue = DispatchQueue(label: "fyi.snag.installed-apps", qos: .utility)

/// Attributes prefetched during the gather phase, so reading them below hits the query's cache
/// rather than an XPC round trip per bundle.
private let INSTALLED_APP_META_ATTRS = [
    NSMetadataItemDisplayNameKey,
    "kMDItemUseCount",
    NSMetadataItemPathKey,
    NSMetadataItemCFBundleIdentifierKey,
]

extension FilePath {
    /// Inside a Trash directory (`~/.Trash`, or a volume's `.Trashes`).
    ///
    /// Spotlight keeps indexing app bundles after they are trashed, so discovery has to drop
    /// them explicitly. A trashed app is not installed and must never be offered for launch.
    var inTrash: Bool {
        components.contains { $0.string.hasPrefix(".Trash") }
    }
}

/// Every installed application, via Spotlight.
func queryInstalledApps(live: Bool = false, handler: @escaping ([InstalledApp]) -> Void) -> MetaQuery {
    MetaQuery(
        scopes: [NSMetadataQueryLocalComputerScope],
        queryString: "kMDItemContentTypeTree == 'com.apple.application-bundle'",
        live: live,
        valueListAttributes: INSTALLED_APP_META_ATTRS,
        handlerQueue: installedAppsQueue
    ) { items in
        let apps = items.compactMap { item -> InstalledApp? in
            // Singular `value(forAttribute:)`, never the plural `values(forAttributes:)`. With
            // valueListAttributes set, the plural API builds a dictionary and inserts every
            // requested attribute; when one resolves to nil (a bundle mid-delete during a live
            // update, say) it inserts nil and throws "object cannot be nil", crashing the app.
            // The singular API returns an optional this guard skips, and still reads from the
            // prefetch cache.
            guard let pathString = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let path = pathString.existingFilePath,
                  !path.inTrash,
                  let bundleIdentifier = item.value(forAttribute: NSMetadataItemCFBundleIdentifierKey) as? String
            else { return nil }

            return InstalledApp(
                path: path,
                name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? path.name.string,
                useCount: item.value(forAttribute: "kMDItemUseCount") as? Int ?? 0,
                bundleIdentifier: bundleIdentifier
            )
        }
        DispatchQueue.main.async { handler(apps) }
    }
}

/// Components that are not user-facing apps: frameworks, XPC services, helpers nested inside
/// another bundle. Spotlight reports all of these as application bundles.
private func matchesAppExcludePath(_ path: String) -> Bool {
    path.contains("/Library/")
        || path.contains("/Frameworks/")
        || path.contains("/PrivateFrameworks/")
        || path.contains(".framework")
        || path.contains(".xpc")
        || (path.contains("/Applications/") && path.contains(".app/Contents"))
}

/// Real apps that happen to live somewhere the exclusions would catch.
private func matchesAppIncludePath(_ path: String) -> Bool {
    path.contains("/System/Library/CoreServices/Finder.app")
        || path.contains(".AppBundle")
        || path.contains("/Library/Caches/JetBrains")
        || path.contains("/Library/Application Support/JetBrains/Toolbox")
        || path.contains("/Applications/Chrome Apps.localized")
        // Xcode nests real, launchable apps (Instruments, Simulator) under its own bundle.
        || (path.hasSuffix(".app") && path.contains("/Applications/Xcode") && {
            guard let r = path.range(of: ".app/Contents/") else { return false }
            return path[r.upperBound...].contains("Applications/")
        }())
}

/// Whether a discovered bundle is something a person would want to launch.
func isAppPathRelevant(_ path: String) -> Bool {
    !matchesAppExcludePath(path) || matchesAppIncludePath(path)
}
