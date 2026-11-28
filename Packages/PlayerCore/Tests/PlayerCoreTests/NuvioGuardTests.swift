import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import PlayerCore

// Nuvio account sync, T12: guard rails. The client may call only the documented calls the feature needs (plan
// section 1.4, `docs/entscheidungen.md` "Nuvio account sync"), and nothing else in the sources may talk to the
// service or touch the stored session. A failure here means a scope change: extend the lists only on purpose.
// No request leaves the process; the scan reads source files only.

// MARK: Allow-list of the calls `NuvioEndpoint` can build

/// Every call the client can produce: method, path below `https://api.nuvio.tv`, and query. Adding, removing or
/// changing an endpoint fails `nuvioEndpointsMatchTheAllowList` until this list is changed on purpose.
private let allowedEndpoints: [NuvioEndpoint: (method: String, path: String, query: String?)] = [
    .signIn: ("POST", "/auth/v1/token", "grant_type=password"),
    .refresh: ("POST", "/auth/v1/token", "grant_type=refresh_token"),
    .signOut: ("POST", "/auth/v1/logout", nil),
    .profiles: ("POST", "/rest/v1/rpc/sync_pull_profiles", nil),
    .addons: ("GET", "/rest/v1/addons", "select=*&profile_id=eq.1&order=sort_order"),
    .collections: ("POST", "/rest/v1/rpc/sync_pull_collections", nil),
    .progress: ("POST", "/rest/v1/rpc/sync_pull_watch_progress", nil),
    .progressCursor: ("POST", "/rest/v1/rpc/sync_get_watch_progress_delta_cursor", nil),
    .progressDelta: ("POST", "/rest/v1/rpc/sync_pull_watch_progress_delta", nil),
    .pushProgress: ("POST", "/rest/v1/rpc/sync_push_watch_progress", nil),
    .watched: ("POST", "/rest/v1/rpc/sync_pull_watched_items", nil),
    .watchedCursor: ("POST", "/rest/v1/rpc/sync_get_watched_items_delta_cursor", nil),
    .watchedDelta: ("POST", "/rest/v1/rpc/sync_pull_watched_items_delta", nil),
]

/// The only write to account data: the watch-progress push.
private let allowedWrites: Set<NuvioEndpoint> = [.pushProgress]

// MARK: Forbidden names in the sources

/// Calls the app must never make. Names from the public API reference v1.3 ("Complete RPC reference", "Sign up",
/// "Profile settings", "Home catalog settings", "Library") and, for calls that reference does not list, from the
/// earlier research of the self-host schema (TV/QR login, device sessions, tracker tokens, provider credentials).
/// Each entry is matched case-insensitively against every source line, comments included.
let nuvioForbiddenNames: [String] = [
    // Full-replace and delete writes (reference: Complete RPC reference).
    "sync_push_addons", "sync_push_collections", "sync_push_profiles", "sync_push_library",
    "sync_delete_profile_data", "sync_delete_library_items", "sync_delete_watch_progress", "sync_delete_watched_items",
    "sync_push_watched_items",
    // Library: out of this step (plan 1.11).
    "sync_pull_library", "sync_get_library_delta_cursor",
    // Settings blobs stay separate (decision D1; reference: Profile settings, Home catalog settings).
    "sync_pull_profile_settings_blob", "sync_push_profile_settings_blob",
    "sync_pull_home_catalog_settings", "sync_push_home_catalog_settings",
    // Sign-up (reference: Sign up, `POST /auth/v1/signup`; also the anonymous session of the QR login).
    "auth/v1/signup", "signup",
    // QR / TV login and device code (research, not in the public reference).
    "start_tv_login_session", "poll_tv_login_session", "approve_tv_login_session", "tv-logins-exchange",
    "start_device_login_session",
    // Device and session registry (research, not in the public reference).
    "register_current_device", "list_my_sessions", "revoke_my_session",
    // Tracker tokens and provider credentials stored on the account (research, not in the public reference).
    "get_tracker_tokens", "sync_pull_provider_credentials", "sync_seed_provider_credentials",
    // Plugins (research): full replace like addons.
    "sync_push_plugins",
]

/// Repository root: this file is `<root>/Packages/PlayerCore/Tests/PlayerCoreTests/NuvioGuardTests.swift`.
private let guardThisFile = URL(fileURLWithPath: #filePath).standardizedFileURL
private let guardRepoRoot = guardThisFile.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private struct SourceFile {
    var relative: String, name: String, text: String, lower: String
    init(relative: String, name: String, text: String) {
        self.relative = relative; self.name = name; self.text = text; lower = text.lowercased()
    }
}

/// All `.swift` files below the PlayerCore sources and (when present) the app sources. Records an issue when the
/// app directory is missing and scans PlayerCore alone. Never contains this test file.
private func guardSources() throws -> [SourceFile] {
    let fm = FileManager.default
    var roots = [guardRepoRoot.appendingPathComponent("Packages/PlayerCore/Sources")]
    let app = guardRepoRoot.appendingPathComponent("App/Sources")
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: app.path, isDirectory: &isDir), isDir.boolValue {
        roots.append(app)
    } else {
        Issue.record("App/Sources not found next to the package (\(app.path)); only PlayerCore was scanned")
    }
    var out: [SourceFile] = []
    for root in roots {
        let e = try #require(fm.enumerator(at: root, includingPropertiesForKeys: nil), "\(root.path)")
        for case let url as URL in e where url.pathExtension == "swift" {
            let std = url.standardizedFileURL
            guard std.path != guardThisFile.path else { continue }
            let rel = String(std.path.dropFirst(guardRepoRoot.standardizedFileURL.path.count + 1))
            out.append(SourceFile(relative: rel, name: std.lastPathComponent,
                                  text: try String(contentsOf: std, encoding: .utf8)))
        }
    }
    return out
}

/// `file:line: text` of every line that contains `needle` (case-insensitive).
private func hits(_ needle: String, in files: [SourceFile]) -> [(file: SourceFile, where: String)] {
    var out: [(SourceFile, String)] = []
    let n = needle.lowercased()
    for f in files where f.lower.contains(n) {
        for (i, line) in f.text.components(separatedBy: "\n").enumerated() where line.lowercased().contains(n) {
            out.append((f, "\(f.relative):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))"))
        }
    }
    return out
}

@Suite struct NuvioGuardTests {

    @Test func nuvioEndpointsMatchTheAllowList() throws {
        #expect(NuvioEndpoint.allCases.count == allowedEndpoints.count)
        #expect(Set(NuvioEndpoint.allCases) == Set(allowedEndpoints.keys))
        #expect(NuvioClient.base.absoluteString == "https://api.nuvio.tv")
        let session = NuvioSession(accessToken: "AT1", refreshToken: "RT1", expiresAt: nil,
                                   userID: "00000000-0000-4000-8000-000000000001")
        let client = NuvioClient(http: FakeSender([]))
        for e in NuvioEndpoint.allCases {
            let want = try #require(allowedEndpoints[e], "\(e) is not on the allow-list")
            #expect(e.method == want.method, "\(e)")
            #expect(e.path == want.path, "\(e)")
            #expect(e.query(profile: 1) == want.query, "\(e)")
            // The request the client really builds: https, the one host, the allowed path and query.
            let r = try client.request(e, profile: 1, session: session)
            let parts = try #require(URLComponents(url: r.url, resolvingAgainstBaseURL: false))
            #expect(parts.scheme == "https", "\(e)")
            #expect(parts.host == "api.nuvio.tv", "\(e)")
            #expect(parts.port == nil, "\(e)")
            #expect(parts.path == want.path, "\(e)")
            #expect(parts.percentEncodedQuery == want.query, "\(e)")
            #expect(r.method == want.method, "\(e)")
        }
        // Only one call writes: everything else that is a POST is an auth call or a pull/cursor RPC.
        for e in NuvioEndpoint.allCases where !allowedWrites.contains(e) {
            #expect(!e.path.contains("sync_push") && !e.path.contains("delete"), "\(e) writes or deletes")
        }
    }

    @Test func nuvioGuardScansTheSources() throws {
        let files = try guardSources()
        // Sanity: the scan sees the files it is meant to guard, so an empty or wrong directory cannot pass silently.
        let names = Set(files.map(\.name))
        #expect(files.count > 50)
        #expect(names.isSuperset(of: ["NuvioClient.swift", "NuvioSession.swift", "NuvioSync.swift"]))
        #expect(!files.contains { $0.name == guardThisFile.lastPathComponent })
    }

    @Test func nuvioForbiddenNamesAppearInNoSource() throws {
        let files = try guardSources()
        for name in nuvioForbiddenNames {
            for h in hits(name, in: files) {
                Issue.record("forbidden Nuvio call \"\(name)\" in \(h.where)")
            }
        }
    }

    /// The service is reached only through `NuvioClient`: its hosts and its API path prefixes appear in no other file.
    @Test func nuvioHostsOnlyInTheClient() throws {
        let files = try guardSources()
        for needle in ["nuvio.tv", "/rest/v1/", "/auth/v1/", "/functions/v1/", "sb_publishable_"] {
            for h in hits(needle, in: files) where h.file.name != "NuvioClient.swift" {
                Issue.record("\"\(needle)\" outside NuvioClient.swift: \(h.where)")
            }
        }
    }

    /// Only the session store reads or writes the stored session: the Keychain name, the device scope and the
    /// store's constants appear in `NuvioSession.swift` alone. Other files go through `NuvioSessionStore` and only
    /// the app wiring may create one.
    @Test func nuvioSessionWrittenOnlyByTheStore() throws {
        let files = try guardSources()
        for needle in ["nuvio.session", "6E757669-6F00-4D00-8000-000000000001", "NuvioSessionStore.secretName",
                       "NuvioSessionStore.deviceScope"] {
            for h in hits(needle, in: files) where h.file.name != "NuvioSession.swift" {
                Issue.record("\"\(needle)\" outside NuvioSession.swift: \(h.where)")
            }
        }
        let storeUsers: Set<String> = ["NuvioSession.swift", "AppModel+Nuvio.swift"]
        for h in hits("NuvioSessionStore(", in: files) where !storeUsers.contains(h.file.name) {
            Issue.record("NuvioSessionStore created outside the app wiring: \(h.where)")
        }
        #expect(NuvioSessionStore.secretName == "nuvio.session")
    }
}
