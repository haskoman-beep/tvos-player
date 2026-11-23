import Foundation

/// Task 2.3: which addresses taken from addon answers (images, streams, subtitles, kit files) may be fetched.
/// Only http/https. Private targets (RFC 1918, link-local, loopback, unique-local IPv6, `.local`, names without a
/// dot) only when the origin (the addon's own address) has the same host, so a LAN addon may point at itself.
public enum TargetPolicy {
    public static func allows(_ url: URL, origin: URL?) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let host = normalizedHost(url), !host.isEmpty else { return false }
        guard isPrivate(host) else { return true }
        guard let origin, let originHost = normalizedHost(origin) else { return false }
        return originHost == host
    }

    static func normalizedHost(_ url: URL) -> String? {
        guard var h = url.host?.lowercased() else { return nil }
        if h.hasPrefix("[") && h.hasSuffix("]") { h = String(h.dropFirst().dropLast()) }
        if h.hasSuffix(".") { h.removeLast() }
        return h
    }

    static func isPrivate(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if let v4 = ipv4(host) { return isPrivateV4(v4) }
        if host.contains(":") { return isPrivateV6(host) }
        return !host.contains(".")
    }

    static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let nums = parts.compactMap { p -> Int? in
            guard !p.isEmpty, p.count <= 3, p.allSatisfy(\.isASCII), let n = Int(p), (0...255).contains(n) else { return nil }
            return n
        }
        return nums.count == 4 ? nums : nil
    }

    static func isPrivateV4(_ a: [Int]) -> Bool {
        switch (a[0], a[1]) {
        case (0, _), (10, _), (127, _): return true
        case (169, 254): return true
        case (172, 16...31): return true
        case (192, 168): return true
        case (100, 64...127): return true   // carrier-grade NAT
        default: return false
        }
    }

    static func isPrivateV6(_ h: String) -> Bool {
        let s = h.split(separator: "%").first.map(String.init) ?? h
        if s == "::1" || s == "::" { return true }
        if s.hasPrefix("::ffff:") { return ipv4(String(s.dropFirst(7))).map(isPrivateV4) ?? true }
        let first = s.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let v = UInt16(first, radix: 16) else { return true }
        if v & 0xffc0 == 0xfe80 { return true }  // link-local fe80::/10
        if v & 0xfe00 == 0xfc00 { return true }  // unique local fc00::/7
        return false
    }
}

/// Task 2.3: headers from addon answers (`behaviorHints.proxyHeaders`) that may be sent on; everything else
/// (cookies, authorization, host, forwarding headers) is dropped. Names are compared case-insensitively.
public enum ProxyHeaderPolicy {
    static let allowed: Set<String> = ["user-agent", "referer", "origin", "accept", "accept-language", "range"]
    public static func filtered(_ headers: [String: String]) -> [String: String] {
        headers.filter { allowed.contains($0.key.lowercased()) }
    }
}
