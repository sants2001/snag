import Foundation

// MARK: - Shared IPC Message Types

//
// These types are used by both the Snag app (server) and the SnagCLI tool (client)
// to exchange requests and responses over a Mach port. Any change here must be
// source-compatible across both targets.

public let SNAG_PORT_ID = "com.santino.Snag.cli" as CFString

// MARK: - SnagCommand

public enum SnagCommand: String, Codable {
    case search
    case index // backwards compat
    case reindex
    case cancelIndex
    case status
    case recents
    case indexAdd
    case indexRemove
    case indexHas
    case explain
}

// MARK: - SnagRequest

public struct SnagRequest: Codable {
    public init(
        command: SnagCommand,
        query: String? = nil,
        maxResults: Int? = nil,
        verbose: Bool? = nil,
        rebuild: Bool? = nil,
        dir: String? = nil,
        suffixPattern: String? = nil,
        folderPrefixes: [String]? = nil,
        dirsOnly: Bool? = nil,
        scopes: [String]? = nil,
        paths: [String]? = nil
    ) {
        self.command = command
        self.query = query
        self.maxResults = maxResults
        self.verbose = verbose
        self.rebuild = rebuild
        self.dir = dir
        self.suffixPattern = suffixPattern
        self.folderPrefixes = folderPrefixes
        self.dirsOnly = dirsOnly
        self.scopes = scopes
        self.paths = paths
    }

    public let command: SnagCommand
    public var query: String?
    public var maxResults: Int?
    public var verbose: Bool?
    public var rebuild: Bool?
    public var dir: String?
    public var suffixPattern: String?
    public var folderPrefixes: [String]?
    public var dirsOnly: Bool?
    public var scopes: [String]?
    public var paths: [String]?

}

// MARK: - SnagSearchResult

public struct SnagSearchResult: Codable {
    public init(path: String, isDir: Bool, score: Int, quality: Int) {
        self.path = path
        self.isDir = isDir
        self.score = score
        self.quality = quality
    }

    public let path: String
    public let isDir: Bool
    public let score: Int
    public let quality: Int

}

// MARK: - SnagScopeStatus

public struct SnagScopeStatus: Codable {
    public init(
        name: String,
        rawValue: String,
        enabled: Bool,
        indexed: Bool,
        indexing: Bool,
        count: Int,
        operation: String? = nil,
        operationCount: Int? = nil,
        lastIndexedAt: Double? = nil
    ) {
        self.name = name
        self.rawValue = rawValue
        self.enabled = enabled
        self.indexed = indexed
        self.indexing = indexing
        self.count = count
        self.operation = operation
        self.operationCount = operationCount
        self.lastIndexedAt = lastIndexedAt
    }

    public let name: String
    public let rawValue: String
    public let enabled: Bool
    public let indexed: Bool
    public let indexing: Bool
    public let count: Int
    public var operation: String?
    public var operationCount: Int?
    /// Epoch seconds of the last successful reindex for this scope. Lets callers detect
    /// a fast reindex that completed between the request and the first status poll.
    public var lastIndexedAt: Double?

}

// MARK: - SnagVolumeStatus

public struct SnagVolumeStatus: Codable {
    public init(
        name: String,
        path: String,
        enabled: Bool,
        indexed: Bool,
        indexing: Bool,
        count: Int,
        operation: String? = nil,
        operationCount: Int? = nil,
        lastIndexedAt: Double? = nil
    ) {
        self.name = name
        self.path = path
        self.enabled = enabled
        self.indexed = indexed
        self.indexing = indexing
        self.count = count
        self.operation = operation
        self.operationCount = operationCount
        self.lastIndexedAt = lastIndexedAt
    }

    public let name: String
    public let path: String
    public let enabled: Bool
    public let indexed: Bool
    public let indexing: Bool
    public let count: Int
    public var operation: String?
    public var operationCount: Int?
    public var lastIndexedAt: Double?

}

// MARK: - SnagResponse

public struct SnagResponse: Codable {
    public init(
        results: [SnagSearchResult]? = nil,
        status: String? = nil,
        error: String? = nil,
        indexCount: Int? = nil,
        searchMs: Double? = nil,
        state: String? = nil,
        operation: String? = nil,
        scopes: [SnagScopeStatus]? = nil,
        volumes: [SnagVolumeStatus]? = nil
    ) {
        self.results = results
        self.status = status
        self.error = error
        self.indexCount = indexCount
        self.searchMs = searchMs
        self.state = state
        self.operation = operation
        self.scopes = scopes
        self.volumes = volumes
    }

    public var results: [SnagSearchResult]?
    public var status: String?
    public var error: String?
    public var indexCount: Int?
    public var searchMs: Double?
    public var state: String?
    public var operation: String?
    public var scopes: [SnagScopeStatus]?
    public var volumes: [SnagVolumeStatus]?

}
