import Foundation

// Nuvio account sync: rows of the public Nuvio API (reference v1.3). Field names mirror the API in Swift style.
// Decoding is lenient: integers accept a number or a numeric string, unknown fields are ignored, missing optional
// fields take their default. A row without its required fields fails alone; the list decoders skip and count it.

// MARK: - Profiles and addons

/// One account profile (`sync_pull_profiles`). `description` shows the index only (no ids, no name).
public struct NuvioProfile: Codable, Equatable, Sendable, CustomStringConvertible {
    public var id: String
    public var userID: String
    /// 1 to 6 in the public client surface.
    public var profileIndex: Int
    public var name: String
    public var avatarColorHex: String?
    /// The profile shares the addons of profile 1.
    public var usesPrimaryAddons: Bool
    public var avatarID: String?
    public var avatarURL: String?
    /// Read-only lock state; PIN checks are not part of the public API.
    public var pinEnabled: Bool
    public var pinLockedUntil: String?
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: String = "", userID: String = "", profileIndex: Int, name: String, avatarColorHex: String? = nil,
                usesPrimaryAddons: Bool = false, avatarID: String? = nil, avatarURL: String? = nil, pinEnabled: Bool = false,
                pinLockedUntil: String? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id; self.userID = userID; self.profileIndex = profileIndex; self.name = name
        self.avatarColorHex = avatarColorHex; self.usesPrimaryAddons = usesPrimaryAddons; self.avatarID = avatarID
        self.avatarURL = avatarURL; self.pinEnabled = pinEnabled; self.pinLockedUntil = pinLockedUntil
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id", profileIndex = "profile_index", avatarColorHex = "avatar_color_hex"
        case usesPrimaryAddons = "uses_primary_addons", avatarID = "avatar_id", avatarURL = "avatar_url"
        case pinEnabled = "pin_enabled", pinLockedUntil = "pin_locked_until", createdAt = "created_at", updatedAt = "updated_at"
    }

    /// Required: `profile_index`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let index = c.nuvioInt(.profileIndex) else { throw NuvioError.decoding("profile_index") }
        self.init(id: c.nuvioString(.id) ?? "", userID: c.nuvioString(.userID) ?? "", profileIndex: index,
                  name: c.nuvioString(.name) ?? "", avatarColorHex: c.nuvioString(.avatarColorHex),
                  usesPrimaryAddons: c.nuvioBool(.usesPrimaryAddons) ?? false, avatarID: c.nuvioString(.avatarID),
                  avatarURL: c.nuvioString(.avatarURL), pinEnabled: c.nuvioBool(.pinEnabled) ?? false,
                  pinLockedUntil: c.nuvioString(.pinLockedUntil), createdAt: c.nuvioString(.createdAt),
                  updatedAt: c.nuvioString(.updatedAt))
    }

    public var description: String { "NuvioProfile(\(profileIndex))" }
}

/// One addon row (`GET rest/v1/addons`). The URL can carry access keys: `description` shows the host only.
public struct NuvioAddon: Codable, Equatable, Sendable, CustomStringConvertible {
    public var id: String
    public var userID: String
    public var profileID: Int
    /// Addon manifest URL.
    public var url: String
    public var name: String?
    public var enabled: Bool
    /// 0-based display order.
    public var sortOrder: Int
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: String = "", userID: String = "", profileID: Int, url: String, name: String? = nil, enabled: Bool = true,
                sortOrder: Int = 0, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id; self.userID = userID; self.profileID = profileID; self.url = url; self.name = name
        self.enabled = enabled; self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, url, name, enabled
        case userID = "user_id", profileID = "profile_id", sortOrder = "sort_order", createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Required: a non-empty `url`. `enabled` defaults to true and `sort_order` to 0 (the push defaults of the API).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let url = c.nuvioString(.url), !url.isEmpty else { throw NuvioError.decoding("url") }
        self.init(id: c.nuvioString(.id) ?? "", userID: c.nuvioString(.userID) ?? "", profileID: c.nuvioInt(.profileID) ?? 0,
                  url: url, name: c.nuvioString(.name), enabled: c.nuvioBool(.enabled) ?? true,
                  sortOrder: c.nuvioInt(.sortOrder) ?? 0, createdAt: c.nuvioString(.createdAt),
                  updatedAt: c.nuvioString(.updatedAt))
    }

    public var description: String { "NuvioAddon(\(LogRedact.url(url)), sortOrder: \(sortOrder), enabled: \(enabled))" }
}

// MARK: - Watch progress

/// One watch-progress row (`sync_pull_watch_progress`, and the data of a delta event). Times in milliseconds.
public struct NuvioProgressRow: Codable, Equatable, Sendable {
    public var id: String?
    public var userID: String?
    public var profileID: Int?
    /// Content identifier as the server has it (`tmdb:550`, `tt…`, …).
    public var contentID: String
    /// `movie` or `series` (kept as sent; other values are possible).
    public var contentType: String
    public var videoID: String
    public var season: Int?
    public var episode: Int?
    public var progressKey: String
    /// Position in ms.
    public var position: Int
    /// Duration in ms.
    public var duration: Int
    /// Epoch ms of the last playback.
    public var lastWatched: Int

    public init(id: String? = nil, userID: String? = nil, profileID: Int? = nil, contentID: String, contentType: String,
                videoID: String, season: Int? = nil, episode: Int? = nil, progressKey: String? = nil, position: Int,
                duration: Int, lastWatched: Int) {
        self.id = id; self.userID = userID; self.profileID = profileID; self.contentID = contentID
        self.contentType = contentType; self.videoID = videoID; self.season = season; self.episode = episode
        self.progressKey = progressKey ?? Self.key(contentID: contentID, season: season, episode: episode)
        self.position = position; self.duration = duration; self.lastWatched = lastWatched
    }

    /// The documented progress key: film `{content_id}`, episode `{content_id}_s{season}e{episode}`.
    /// Used locally only (matching deletes and outbox entries); a push never sends it.
    public static func key(contentID: String, season: Int?, episode: Int?) -> String {
        guard let s = season, let e = episode else { return contentID }
        return "\(contentID)_s\(s)e\(e)"
    }

    enum CodingKeys: String, CodingKey {
        case id, season, episode, position, duration
        case userID = "user_id", profileID = "profile_id", contentID = "content_id", contentType = "content_type"
        case videoID = "video_id", progressKey = "progress_key", lastWatched = "last_watched"
    }

    /// Required: a non-empty `content_id`, `position`, `duration` and `last_watched`. A missing `progress_key` is
    /// computed from `content_id`, `season` and `episode`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let content = c.nuvioString(.contentID), !content.isEmpty else { throw NuvioError.decoding("content_id") }
        guard let position = c.nuvioInt(.position), let duration = c.nuvioInt(.duration),
              let last = c.nuvioInt(.lastWatched) else { throw NuvioError.decoding("position") }
        let key = c.nuvioString(.progressKey).flatMap { $0.isEmpty ? nil : $0 }
        self.init(id: c.nuvioString(.id), userID: c.nuvioString(.userID), profileID: c.nuvioInt(.profileID),
                  contentID: content, contentType: c.nuvioString(.contentType) ?? "", videoID: c.nuvioString(.videoID) ?? "",
                  season: c.nuvioInt(.season), episode: c.nuvioInt(.episode), progressKey: key, position: position,
                  duration: duration, lastWatched: last)
    }
}

/// Operation of a delta event.
public enum NuvioOperation: String, Codable, Equatable, Sendable { case upsert, delete }

/// One event of `sync_pull_watch_progress_delta`. An upsert always carries its `row`; a delete is identified by
/// `progressKey` and carries the row only when the server sent readable row fields.
public struct NuvioProgressEvent: Equatable, Sendable, Decodable {
    public var eventID: Int
    public var operation: NuvioOperation
    public var progressKey: String
    public var row: NuvioProgressRow?

    public init(eventID: Int, operation: NuvioOperation, progressKey: String, row: NuvioProgressRow?) {
        self.eventID = eventID; self.operation = operation; self.progressKey = progressKey; self.row = row
    }

    enum CodingKeys: String, CodingKey {
        case eventID = "event_id", operation, progressKey = "progress_key", contentID = "content_id", season, episode
    }

    /// Required: `event_id`, a known `operation`; for an upsert the row fields, for a delete a progress key (sent, or
    /// computed from `content_id`, `season` and `episode`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.nuvioInt(.eventID) else { throw NuvioError.decoding("event_id") }
        guard let op = c.nuvioString(.operation).flatMap(NuvioOperation.init(rawValue:)) else {
            throw NuvioError.decoding("operation")
        }
        let row = try? NuvioProgressRow(from: decoder)
        if op == .upsert, row == nil { throw NuvioError.decoding("row") }
        var key = c.nuvioString(.progressKey).flatMap { $0.isEmpty ? nil : $0 } ?? row?.progressKey
        if key == nil, let content = c.nuvioString(.contentID), !content.isEmpty {
            key = NuvioProgressRow.key(contentID: content, season: c.nuvioInt(.season), episode: c.nuvioInt(.episode))
        }
        guard let key else { throw NuvioError.decoding("progress_key") }
        self.init(eventID: id, operation: op, progressKey: key, row: row)
    }
}

/// One progress entry of `sync_push_watch_progress`. Integers in ms; `season`/`episode` are left out of the JSON
/// when nil (films). No `progress_key`: the server computes it.
public struct NuvioProgressPush: Codable, Equatable, Sendable {
    public var contentID: String
    public var contentType: String
    public var videoID: String
    public var season: Int?
    public var episode: Int?
    public var position: Int
    public var duration: Int
    public var lastWatched: Int

    public init(contentID: String, contentType: String, videoID: String, season: Int? = nil, episode: Int? = nil,
                position: Int, duration: Int, lastWatched: Int) {
        self.contentID = contentID; self.contentType = contentType; self.videoID = videoID; self.season = season
        self.episode = episode; self.position = position; self.duration = duration; self.lastWatched = lastWatched
    }

    enum CodingKeys: String, CodingKey {
        case season, episode, position, duration
        case contentID = "content_id", contentType = "content_type", videoID = "video_id", lastWatched = "last_watched"
    }
}

// MARK: - Watch history

/// One watched-history item (`sync_pull_watched_items`, and the data of a delta event).
public struct NuvioWatchedItem: Codable, Equatable, Sendable {
    public var id: String?
    public var userID: String?
    public var profileID: Int?
    public var contentID: String
    /// `movie` or `series` (kept as sent).
    public var contentType: String
    public var title: String?
    public var season: Int?
    public var episode: Int?
    /// Epoch ms; 0 only on a delete event that did not send it.
    public var watchedAt: Int
    public var createdAt: String?

    public init(id: String? = nil, userID: String? = nil, profileID: Int? = nil, contentID: String, contentType: String,
                title: String? = nil, season: Int? = nil, episode: Int? = nil, watchedAt: Int, createdAt: String? = nil) {
        self.id = id; self.userID = userID; self.profileID = profileID; self.contentID = contentID
        self.contentType = contentType; self.title = title; self.season = season; self.episode = episode
        self.watchedAt = watchedAt; self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, season, episode
        case userID = "user_id", profileID = "profile_id", contentID = "content_id", contentType = "content_type"
        case watchedAt = "watched_at", createdAt = "created_at"
    }

    /// Required: a non-empty `content_id` and `watched_at`.
    public init(from decoder: Decoder) throws {
        try self.init(decoder, watchedAtRequired: true)
    }

    init(_ decoder: Decoder, watchedAtRequired: Bool) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let content = c.nuvioString(.contentID), !content.isEmpty else { throw NuvioError.decoding("content_id") }
        let at = c.nuvioInt(.watchedAt)
        if watchedAtRequired, at == nil { throw NuvioError.decoding("watched_at") }
        self.init(id: c.nuvioString(.id), userID: c.nuvioString(.userID), profileID: c.nuvioInt(.profileID),
                  contentID: content, contentType: c.nuvioString(.contentType) ?? "", title: c.nuvioString(.title),
                  season: c.nuvioInt(.season), episode: c.nuvioInt(.episode), watchedAt: at ?? 0,
                  createdAt: c.nuvioString(.createdAt))
    }
}

/// One event of `sync_pull_watched_items_delta`. The item is identified by `content_id`, `season` and `episode`;
/// a delete without `watched_at` gets 0 there.
public struct NuvioWatchedEvent: Equatable, Sendable, Decodable {
    public var eventID: Int
    public var operation: NuvioOperation
    public var item: NuvioWatchedItem

    public init(eventID: Int, operation: NuvioOperation, item: NuvioWatchedItem) {
        self.eventID = eventID; self.operation = operation; self.item = item
    }

    enum CodingKeys: String, CodingKey { case eventID = "event_id", operation }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.nuvioInt(.eventID) else { throw NuvioError.decoding("event_id") }
        guard let op = c.nuvioString(.operation).flatMap(NuvioOperation.init(rawValue:)) else {
            throw NuvioError.decoding("operation")
        }
        self.init(eventID: id, operation: op, item: try NuvioWatchedItem(decoder, watchedAtRequired: op == .upsert))
    }
}

// MARK: - Pages

/// One page of rows as the server sent it. `received` counts every row, readable or not: compare it with the
/// requested page size to tell whether another page may follow. `lastEventID` (delta pages) is the highest readable
/// `event_id` of all received rows, unreadable ones included, so a cursor can move past a row that will never read.
public struct NuvioPage<Row: Sendable & Equatable>: Sendable, Equatable {
    public var rows: [Row]
    public var received: Int
    public var lastEventID: Int?

    public init(rows: [Row], received: Int? = nil, lastEventID: Int? = nil) {
        self.rows = rows; self.received = received ?? rows.count; self.lastEventID = lastEventID
    }

    /// Rows that could not be read and were left out.
    public var skipped: Int { max(0, received - rows.count) }
}

/// One list element: the row or nil, plus its `event_id` when readable (also for an unreadable row).
struct NuvioLossyRow<Row: Decodable>: Decodable {
    let value: Row?
    let eventID: Int?

    private enum Keys: String, CodingKey { case eventID = "event_id" }

    init(from decoder: Decoder) throws {
        value = try? Row(from: decoder)
        eventID = (try? decoder.container(keyedBy: Keys.self))?.nuvioInt(.eventID)
    }
}

extension NuvioPage where Row: Decodable {
    /// A JSON array, row by row. Anything but an array throws `NuvioError.decoding(context)`.
    static func decode(_ data: Data, context: String) throws -> NuvioPage {
        guard let list = try? JSONDecoder().decode([NuvioLossyRow<Row>].self, from: data) else {
            throw NuvioError.decoding(context)
        }
        return NuvioPage(rows: list.compactMap(\.value), received: list.count, lastEventID: list.compactMap(\.eventID).max())
    }
}

// MARK: - Cursor, collections, error body

enum NuvioPayload {
    /// A delta cursor: a bare integer, a numeric string, `null` or an empty body (0), or one value wrapped in a
    /// one-element array or a one-field object (`[{"sync_get_…":42}]`). Negative values count as 0.
    static func cursor(_ data: Data) throws -> Int {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return 0 }
        guard let v = try? JSONDecoder().decode(JSONValue.self, from: data), let n = cursor(v) else {
            throw NuvioError.decoding("cursor")
        }
        return max(0, n)
    }

    private static func cursor(_ v: JSONValue, depth: Int = 0) -> Int? {
        guard depth < 4 else { return nil }
        switch v {
        case .null: return 0
        case .int(let i): return Int(exactly: i)
        case .uint(let u): return Int(exactly: u)
        case .double(let d): return d.isFinite && d.rounded() == d ? Int(exactly: d) : nil
        case .string(let s): return Int(s.trimmingCharacters(in: .whitespaces))
        case .array(let a): return a.isEmpty ? 0 : a.count == 1 ? cursor(a[0], depth: depth + 1) : nil
        case .object(let o): return o.count == 1 ? cursor(o.first!.value, depth: depth + 1) : nil
        case .bool: return nil
        }
    }

    /// `sync_pull_collections` → the `collections_json` array as JSON bytes for `NuvioImport.parse`. Takes the first
    /// row; `collections_json` may be an array, a single object (wrapped) or a string holding either. No row or
    /// `null` → `[]`. Output is re-encoded with sorted keys, so both forms give the same bytes.
    static func collections(_ data: Data) throws -> Data {
        guard let top = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw NuvioError.decoding("collections") }
        let row: JSONValue?
        switch top {
        case .array(let rows): row = rows.first
        case .object: row = top
        case .null: row = nil
        default: throw NuvioError.decoding("collections")
        }
        guard case .object(let o)? = row else {
            if row == nil { return Data("[]".utf8) }
            throw NuvioError.decoding("collections")
        }
        var blob = o["collections_json"] ?? .null
        if case .string(let s) = blob {
            guard let inner = try? JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) else {
                throw NuvioError.decoding("collections_json")
            }
            blob = inner
        }
        let list: [JSONValue]
        switch blob {
        case .null: list = []
        case .array(let a): list = a
        case .object: list = [blob]
        default: throw NuvioError.decoding("collections_json")
        }
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(list)
    }

    /// The `code` of an error body (`{"code":"PGRST202",…}`; auth errors may put it in `error_code`). Only a short
    /// identifier is kept, never `message`, `details` or `hint`, so nothing the server echoes can reach a log.
    static func errorCode(_ data: Data) -> String? {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        for key in ["code", "error_code"] {
            if case .string(let s)? = o[key], isSafeCode(s) { return s }
        }
        return nil
    }

    static func isSafeCode(_ s: String) -> Bool {
        (1...64).contains(s.count) && s.unicodeScalars.allSatisfy { c in
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_" || c == "-" || c == "."
        }
    }
}

// MARK: - Lenient field readers

extension KeyedDecodingContainer {
    /// An integer from a number (an integral double too) or a numeric string; nil when missing, null or unreadable.
    func nuvioInt(_ key: Key) -> Int? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let d = try? decode(Double.self, forKey: key), d.isFinite, d.rounded() == d { return Int(exactly: d) }
        if let s = try? decode(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespaces)
            if let i = Int(t) { return i }
            if let d = Double(t), d.isFinite, d.rounded() == d { return Int(exactly: d) }
        }
        return nil
    }

    /// A string; nil when missing, null or not a string.
    func nuvioString(_ key: Key) -> String? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        return try? decode(String.self, forKey: key)
    }

    /// A boolean from `true`/`false`, 0/1 or the strings "true"/"false"; nil otherwise.
    func nuvioBool(_ key: Key) -> Bool? {
        guard contains(key), (try? decodeNil(forKey: key)) != true else { return nil }
        if let b = try? decode(Bool.self, forKey: key) { return b }
        if let i = try? decode(Int.self, forKey: key), i == 0 || i == 1 { return i == 1 }
        switch (try? decode(String.self, forKey: key))?.lowercased() {
        case "true"?: return true
        case "false"?: return false
        default: return nil
        }
    }
}
