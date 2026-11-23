import Foundation
import Testing
@testable import PlayerCore

// Task 2.3: which addresses from addon answers may be fetched.

private func u(_ s: String) -> URL { URL(string: s)! }

@Test func targetPolicyRejectsNonHTTPSchemes() {
    #expect(!TargetPolicy.allows(u("file:///etc/passwd"), origin: u("https://addon.example.com/manifest.json")))
    #expect(!TargetPolicy.allows(u("ftp://files.example.com/a.srt"), origin: nil))
}

@Test func targetPolicyAllowsPublicHosts() {
    #expect(TargetPolicy.allows(u("https://images.example.org/p.jpg"), origin: u("https://addon.example.com")))
    #expect(TargetPolicy.allows(u("http://cdn.example.net/v.mp4"), origin: nil))
}

@Test func targetPolicyRejectsLoopbackFromForeignOrigin() {
    let origin = u("https://addon.example.com/manifest.json")
    #expect(!TargetPolicy.allows(u("http://127.0.0.1:8080/x"), origin: origin))
    #expect(!TargetPolicy.allows(u("http://localhost/x"), origin: origin))
    #expect(!TargetPolicy.allows(u("http://[::1]/x"), origin: origin))
}

@Test func targetPolicyRejectsPrivateNetworkFromForeignOrigin() {
    let origin = u("https://addon.example.com/manifest.json")
    for s in ["http://10.0.0.5/a", "http://172.16.3.4/a", "http://172.31.255.1/a", "http://192.168.1.20/a",
              "http://169.254.10.10/a", "http://[fe80::1]/a", "http://[fd00::5]/a", "http://0.0.0.0/a"] {
        #expect(!TargetPolicy.allows(u(s), origin: origin), "\(s)")
    }
    // 172.32.x is public, not RFC 1918
    #expect(TargetPolicy.allows(u("http://172.32.0.1/a"), origin: origin))
}

@Test func targetPolicyAllowsPrivateNetworkWithSameOrigin() {
    let origin = u("http://192.168.1.20:7000/manifest.json")
    #expect(TargetPolicy.allows(u("http://192.168.1.20:7000/stream/a.mkv"), origin: origin))
    #expect(TargetPolicy.allows(u("http://192.168.1.20/poster.jpg"), origin: origin))
    #expect(!TargetPolicy.allows(u("http://192.168.1.21/poster.jpg"), origin: origin))
    #expect(!TargetPolicy.allows(u("http://192.168.1.20/poster.jpg"), origin: nil))
}

@Test func targetPolicyTreatsLocalAndDotlessNamesAsPrivate() {
    let origin = u("https://addon.example.com")
    #expect(!TargetPolicy.allows(u("http://nas.local/a.jpg"), origin: origin))
    #expect(!TargetPolicy.allows(u("http://router/a.jpg"), origin: origin))
    #expect(TargetPolicy.allows(u("http://nas.local:8080/a.jpg"), origin: u("http://NAS.local:8080/manifest.json")))
}

@Test func proxyHeaderPolicyKeepsOnlyAllowedHeaders() {
    let h = ProxyHeaderPolicy.filtered(["user-agent": "VLC", "Referer": "https://r.example.com", "Origin": "o",
                                        "Accept": "*/*", "Accept-Language": "de", "Range": "bytes=0-",
                                        "Cookie": "s=1", "Authorization": "Bearer x", "Host": "evil", "X-Forwarded-For": "1"])
    #expect(Set(h.keys) == ["user-agent", "Referer", "Origin", "Accept", "Accept-Language", "Range"])
    #expect(h["user-agent"] == "VLC")
}
