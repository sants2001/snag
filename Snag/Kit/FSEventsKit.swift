//
//  Filesystem watching, on Apple's FSEvents C API directly.
//
//  Snag reached FSEvents through Lowtech, which wraps eonil/FSEvents. That package has **no
//  licence file** either, making it the third all-rights-reserved dependency in the chain after
//  Lowtech and swift-ignore. Swapping one unlicensed wrapper for another would not help, so this
//  talks to the system API directly and adds no dependency at all.
//
//  The shape mirrors what the call sites in FuzzyClient and ScriptManager already expect:
//  start/stop keyed by an ObjectIdentifier, a coalescing latency, and a handler receiving a path
//  and a flag set.
//

import Foundation
import System

// MARK: - SnagFSEvent

struct SnagFSEvent {
    /// Which change occurred. Optional to match how call sites already guard it; FSEvents can
    /// deliver housekeeping events (history-done, mount, unmount) carrying no item flags.
    let flag: SnagFSEventFlags?
    let path: String
}

// MARK: - SnagFSEventFlags

struct SnagFSEventFlags: OptionSet {
    init(rawValue: UInt32) { self.rawValue = rawValue }

    static let itemCreated = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemCreated))
    static let itemRemoved = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemRemoved))
    static let itemRenamed = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemRenamed))
    static let itemModified = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemModified))
    static let itemIsDir = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemIsDir))
    static let itemIsFile = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemIsFile))
    /// chown, chmod or an xattr change. Snag watches this because a permissions change can make
    /// a path readable or unreadable without its name ever changing.
    static let itemChangeOwner = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemChangeOwner))
    static let itemInodeMetaMod = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemInodeMetaMod))
    static let itemXattrMod = SnagFSEventFlags(rawValue: UInt32(kFSEventStreamEventFlagItemXattrMod))

    let rawValue: UInt32

    /// True if any of `others` is present. Named to match the call sites, which read
    /// `flags.hasElements(from: [.itemCreated, .itemRemoved, ...])`.
    func hasElements(from others: SnagFSEventFlags) -> Bool {
        !intersection(others).isEmpty
    }
}

// MARK: - SnagFSEvents

enum SnagFSEvents {
    /// Begin watching `paths`. A second call with the same `id` is ignored, matching the
    /// previous behaviour that callers rely on to avoid stacking duplicate streams.
    ///
    /// `latency` is FSEvents' own coalescing window in seconds. It matters a lot here: Snag
    /// watches `/Users` and `/Applications`, and a package install or a build can produce tens
    /// of thousands of events. Letting the system batch them is far cheaper than filtering them
    /// individually on our side.
    static func startWatching(
        paths: [String],
        for id: ObjectIdentifier,
        latency: TimeInterval = 0,
        with handler: @escaping (SnagFSEvent) -> Void
    ) throws {
        queue.async {
            guard streams[id] == nil else { return }

            let box = HandlerBox(handler)
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passRetained(box).toOpaque(),
                retain: nil,
                release: { pointer in
                    guard let pointer else { return }
                    Unmanaged<HandlerBox>.fromOpaque(pointer).release()
                },
                copyDescription: nil
            )

            let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
                // `info` is non-optional in this signature; `paths` is a plain raw pointer.
                guard let info else { return }
                let box = Unmanaged<HandlerBox>.fromOpaque(info).takeUnretainedValue()
                // kFSEventStreamCreateFlagUseCFTypes makes this a CFArray of CFString.
                let pathArray = unsafeBitCast(paths, to: NSArray.self)
                for i in 0 ..< count {
                    guard let path = pathArray[i] as? String else { continue }
                    let raw = flags[i]
                    box.handler(SnagFSEvent(
                        flag: raw == 0 ? nil : SnagFSEventFlags(rawValue: raw),
                        path: path
                    ))
                }
            }

            // .noDefer delivers the first event immediately rather than after a full latency
            // window, so a single file change is not invisible for `latency` seconds.
            // .fileEvents reports individual files instead of only their parent directories,
            // which the index needs to update a single entry rather than rescan a tree.
            let flags = UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            ) else {
                // Balance the passRetained above; the release callback never runs when creation
                // fails, so without this the box leaks on every failed attempt.
                Unmanaged<HandlerBox>.fromOpaque(context.info!).release()
                return
            }

            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
            streams[id] = stream
        }
    }

    static func stopWatching(for id: ObjectIdentifier) {
        queue.async {
            guard let stream = streams.removeValue(forKey: id) else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Serialises access to `streams`. Every mutation goes through here, which is why the
    /// dictionary needs no further locking.
    private static let queue = DispatchQueue(label: "fyi.snag.fsevents", qos: .utility)
    nonisolated(unsafe) private static var streams: [ObjectIdentifier: FSEventStreamRef] = [:]

    /// Carries the Swift closure across the C callback boundary, which can only pass a raw
    /// pointer.
    private final class HandlerBox {
        init(_ handler: @escaping (SnagFSEvent) -> Void) { self.handler = handler }
        let handler: (SnagFSEvent) -> Void
    }
}
