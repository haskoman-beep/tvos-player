import Foundation

/// Nuvio account sync: the login of the one Nuvio account of this device (Supabase-style tokens).
/// Kept only in the secret store (`NuvioSessionStore`), never in a profile, a blob or a backup.
/// `description`, `debugDescription` and the mirror show no token and no user id, so a stray log line cannot leak them.
public struct NuvioSession: Codable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable {
    public var accessToken: String
    public var refreshToken: String
    /// nil = expiry unknown (only from an older or damaged entry; sign-in and refresh always set it).
    public var expiresAt: Date?
    public var userID: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date?, userID: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.userID = userID
    }

    /// Margin before the expiry from which the access token is renewed (same as `SyncToken.refreshLeeway`).
    public static let refreshLeeway: TimeInterval = 60

    /// True once less than `refreshLeeway` is left. Without an expiry date: false (the 401 path still renews).
    public func needsRefresh(now: Date = Date()) -> Bool {
        guard let e = expiresAt else { return false }
        return e.timeIntervalSince(now) < Self.refreshLeeway
    }

    public var description: String {
        "NuvioSession(‹verborgen›, expiresAt: \(expiresAt.map { "\($0.timeIntervalSince1970)" } ?? "nil"))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["expiresAt": expiresAt as Any], displayStyle: .struct) }
}

/// Reads and writes the Nuvio session through `SecretStore` (the Keychain in the app, `…ThisDeviceOnly`).
/// One entry for the whole device under `deviceScope`, a fixed UUID that is never a profile id: the profile secret
/// migration (`SecretMigration`) only visits real profile ids and so never sees, copies, mirrors or removes it.
public struct NuvioSessionStore: Sendable {
    public static let secretName = "nuvio.session"
    /// Fixed device scope ("nuvio" in the first bytes). Must never change: the entry would be lost.
    public static let deviceScope = UUID(uuidString: "6E757669-6F00-4D00-8000-000000000001")!

    let store: SecretStore

    public init(store: SecretStore) { self.store = store }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    /// The stored session; nil without one, when the entry is unreadable, or when a token is empty.
    public func load() -> NuvioSession? {
        guard let text = store.get(Self.secretName, profile: Self.deviceScope) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard let s = try? d.decode(NuvioSession.self, from: Data(text.utf8)),
              !s.accessToken.isEmpty, !s.refreshToken.isEmpty else { return nil }
        return s
    }

    public func save(_ s: NuvioSession) throws {
        let data = try Self.encoder.encode(s)
        try store.set(String(decoding: data, as: UTF8.self), name: Self.secretName, profile: Self.deviceScope)
    }

    /// Removes only the session entry (other entries of the device scope stay).
    public func wipe() throws {
        try store.set(nil, name: Self.secretName, profile: Self.deviceScope)
    }
}
