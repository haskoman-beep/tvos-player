import Foundation
import Testing
@testable import PlayerCore

// Task 1.5: HMAC-SHA256 over the remote log body (header `X-Player-Sig`), pure Swift.

@Test func logSignatureMatchesKnownVector() {
    // RFC 4231, test case 2.
    let sig = LogSignature.sign(body: Data("what do ya want for nothing?".utf8), secret: "Jefe")
    #expect(sig == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    // SHA-256 of "abc" (FIPS 180-2) and of the empty input, so the hash itself is checked too.
    #expect(LogSignature.hex(SHA256Digest.hash(Data("abc".utf8)))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    #expect(LogSignature.hex(SHA256Digest.hash(Data()))
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    // RFC 4231, test case 6: key longer than one block (131 bytes of 0xaa).
    let longKey = LogSignature.mac(body: Data("Test Using Larger Than Block-Size Key - Hash Key First".utf8),
                                   key: Data(repeating: 0xaa, count: 131))
    #expect(LogSignature.hex(longKey) == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
}

@Test func logSignatureChangesWithBody() {
    let secret = "nur-ein-test-geheimnis"
    let a = LogSignature.sign(body: Data(#"[{"m":"eins"}]"#.utf8), secret: secret)
    let b = LogSignature.sign(body: Data(#"[{"m":"zwei"}]"#.utf8), secret: secret)
    #expect(a != b)
    #expect(a.count == 64 && a == a.lowercased())
    #expect(LogSignature.sign(body: Data(#"[{"m":"eins"}]"#.utf8), secret: "anderes") != a)
    #expect(LogSignature.verify(body: Data(#"[{"m":"eins"}]"#.utf8), secret: secret, signature: a))
    #expect(LogSignature.verify(body: Data(#"[{"m":"eins"}]"#.utf8), secret: secret, signature: a.uppercased()))
    #expect(!LogSignature.verify(body: Data(#"[{"m":"zwei"}]"#.utf8), secret: secret, signature: a))
    #expect(!LogSignature.verify(body: Data(), secret: secret, signature: ""))
    #expect(LogSignature.header == "X-Player-Sig")
}
