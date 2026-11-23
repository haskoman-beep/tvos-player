import Foundation

/// Task 1.4: authenticated encryption under a key derived from the code shown on the TV. The app implements it with
/// CryptoKit (`HKDF<SHA256>` → 32-byte key, `ChaChaPoly`); PlayerCore only defines the file around it, so the format is
/// tested on Linux with a stand-in cipher.
public protocol BackupCipher: Sendable {
    /// `header` is authenticated, not encrypted. `tag` must be `BackupCrypto.tagLength` bytes.
    func seal(_ plaintext: Data, code: String, salt: Data, nonce: Data, header: Data) throws -> (ciphertext: Data, tag: Data)
    /// Throws if the code is wrong or any byte of header, ciphertext or tag was changed.
    func open(_ ciphertext: Data, tag: Data, code: String, salt: Data, nonce: Data, header: Data) throws -> Data
}

public enum BackupCryptoError: Error, Equatable, Sendable {
    case notSealed
    case unsupportedVersion(Int)
    case damaged
    case wrongCodeOrDamaged
    /// Not 12 characters of `BackupCrypto.codeAlphabet` (dashes, spaces and case aside).
    case invalidCode
    /// Written with a key derivation this build does not read (for example the early six-digit code, id 1).
    case unsupportedCode(Int)
}

/// Encrypted backup file `player-sicherung.enc`, format version 1.
///
/// The file is text, so it survives the phone page's form field and a file chosen there:
///
///     PLAYER-SICHERUNG-1\n
///     <base64 of the binary container>\n
///
/// Binary container (all lengths in bytes):
///
///     offset  length  field
///     0       4       magic "PLYS"
///     4       1       format version = 1
///     5       1       key derivation = 2: HKDF-SHA256, input = the 12 ASCII characters of the code in canonical
///                     form (upper case, no dashes or spaces, alphabet `BackupCrypto.codeAlphabet`), salt below,
///                     info "player-sicherung v1", 32-byte key. Id 1 (six digits) was never shipped and is refused
///                     with `unsupportedCode(1)`.
///     6       16      salt (random per file)
///     22      12      nonce (random per file; ChaChaPoly)
///     34      n       ciphertext of the full profile export (`ProfileStore.exportData(_, includeSecrets: true)`)
///     34+n    16      authentication tag (Poly1305)
///
/// Bytes 0..<34 are the header and go into the authentication as additional data, so a changed version, salt or nonce
/// fails like a wrong code. A reader rejects other magic, other versions and other key derivations.
///
/// The code is shown as three groups of four („K7QM-2XPA-9DRT“): 12 characters from 31 (no 0/O, 1/I/L), about 59 bits.
public struct BackupCrypto: Sendable {
    public static let armorLine = "PLAYER-SICHERUNG-1"
    public static let fileName = "player-sicherung.enc"
    public static let hkdfInfo = Data("player-sicherung v1".utf8)
    static let magic = Data("PLYS".utf8)
    static let version: UInt8 = 1
    /// Key derivation ids: 1 = six digits (never shipped, refused), 2 = 12 characters.
    static let kdfHKDFSHA256Code6: UInt8 = 1
    static let kdfHKDFSHA256Code12: UInt8 = 2
    /// Upper-case letters and digits without 0, O, 1, I and L.
    public static let codeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let codeLength = 12
    public static let saltLength = 16
    public static let nonceLength = 12
    public static let tagLength = 16
    static let headerLength = 4 + 1 + 1 + saltLength + nonceLength

    let cipher: any BackupCipher
    let random: @Sendable (Int) -> Data

    public init(cipher: any BackupCipher, random: @escaping @Sendable (Int) -> Data = BackupCrypto.systemRandom) {
        self.cipher = cipher; self.random = random
    }

    public func seal(_ plaintext: Data, code: String) throws -> Data {
        guard let code = Self.normalizedCode(code) else { throw BackupCryptoError.invalidCode }
        let salt = random(Self.saltLength), nonce = random(Self.nonceLength)
        let header = Self.magic + Data([Self.version, Self.kdfHKDFSHA256Code12]) + salt + nonce
        let (c, tag) = try cipher.seal(plaintext, code: code, salt: salt, nonce: nonce, header: header)
        guard tag.count == Self.tagLength else { throw BackupCryptoError.damaged }
        return Data((Self.armorLine + "\n" + (header + c + tag).base64EncodedString() + "\n").utf8)
    }

    public func open(_ file: Data, code: String) throws -> Data {
        let bin = try Self.unarmor(file)
        guard let code = Self.normalizedCode(code) else { throw BackupCryptoError.invalidCode }
        guard bin.count >= Self.headerLength + Self.tagLength else { throw BackupCryptoError.damaged }
        let b = [UInt8](bin)
        guard Data(b[0..<4]) == Self.magic else { throw BackupCryptoError.damaged }
        guard b[4] == Self.version else { throw BackupCryptoError.unsupportedVersion(Int(b[4])) }
        guard b[5] == Self.kdfHKDFSHA256Code12 else { throw BackupCryptoError.unsupportedCode(Int(b[5])) }
        let header = Data(b[0..<Self.headerLength])
        let salt = Data(b[6..<(6 + Self.saltLength)]), nonce = Data(b[(6 + Self.saltLength)..<Self.headerLength])
        let c = Data(b[Self.headerLength..<(b.count - Self.tagLength)]), tag = Data(b[(b.count - Self.tagLength)...])
        do { return try cipher.open(c, tag: tag, code: code, salt: salt, nonce: nonce, header: header) }
        catch { throw BackupCryptoError.wrongCodeOrDamaged }
    }

    /// Text armor → binary container. `notSealed` without the first line, `damaged` for broken base64.
    public static func unarmor(_ file: Data) throws -> Data {
        guard let text = String(data: file, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.hasPrefix(armorLine) else { throw BackupCryptoError.notSealed }
        let body = text.dropFirst(armorLine.count).filter { !$0.isWhitespace }
        guard let bin = Data(base64Encoded: String(body)) else { throw BackupCryptoError.damaged }
        return bin
    }

    public static func isSealed(_ data: Data) -> Bool {
        guard let head = String(data: data.prefix(armorLine.count + 8), encoding: .utf8) else { return false }
        return head.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(armorLine)
    }

    /// Canonical form for the key derivation: 12 characters of `codeAlphabet`, upper case, without dashes and spaces.
    /// Input is accepted in any case and with or without dashes/spaces („k7qm 2xpa-9drt“).
    public static func normalizedCode(_ s: String) -> String? {
        let d = s.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "\u{2013}" && $0 != "\u{2011}" }
        return d.count == codeLength && d.allSatisfy({ codeAlphabet.contains($0) }) ? d : nil
    }

    /// Display form: three groups of four, „K7QM-2XPA-9DRT“. `nil` for anything `normalizedCode` refuses.
    public static func groupedCode(_ s: String) -> String? {
        guard let c = normalizedCode(s).map(Array.init) else { return nil }
        return [c[0..<4], c[4..<8], c[8..<12]].map { String($0) }.joined(separator: "-")
    }

    /// A new random code in display form (`SystemRandomNumberGenerator`, uniform over the alphabet).
    public static func makeCode() -> String {
        var g = SystemRandomNumberGenerator()
        return makeCode(using: &g)
    }

    static func makeCode<G: RandomNumberGenerator>(using g: inout G) -> String {
        let raw = String((0..<codeLength).map { _ in codeAlphabet.randomElement(using: &g)! })
        return groupedCode(raw)!
    }

    public static func systemRandom(_ n: Int) -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<n).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }
}

// MARK: Export without secrets

/// Addon addresses without their access part (user/password, query, configuration in the path).
public enum AddonAccess {
    /// Keeps scheme, host, port and short plain path segments (`/stremio/v1`); drops user info, query, fragment and every
    /// path segment that looks like a configuration: 20 characters or more, or one of `% = | , { } ; : ~ @ +`
    /// (Stremio addons put debrid and indexer keys there, plain or base64). A last segment `manifest.json` stays; any
    /// other last segment goes through the same filter.
    public static func publicManifestURL(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Characters outside RFC 3986 (`|`, `{` in hand-made configurations) are encoded first, so the host survives.
        let lenient = t.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlFragmentAllowed.union(CharacterSet(charactersIn: "#%")))
        guard var c = URLComponents(string: t) ?? lenient.flatMap({ URLComponents(string: $0) }), c.host != nil else { return "" }
        c.user = nil; c.password = nil; c.query = nil; c.fragment = nil
        var segs = c.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let last = segs.last?.lowercased() == "manifest.json" ? segs.popLast() : nil
        let marks = Set("%=|,{};:~@+")
        segs = segs.filter { $0.count < 20 && !$0.contains(where: { marks.contains($0) }) }
        let kept = segs + (last.map { [$0] } ?? [])
        c.percentEncodedPath = kept.isEmpty ? "" : "/" + kept.joined(separator: "/")
        return c.string ?? ""
    }
}

extension StoredProfiles {
    /// Task 1.4: the same structure without `apiKeys`, `syncTokens` and the access part of addon addresses. Empty maps
    /// stay in the file, so build 249 reads it as before.
    public func withoutSecrets() -> StoredProfiles {
        var s = self
        for i in s.profiles.indices {
            s.profiles[i].apiKeys = [:]
            s.profiles[i].syncTokens = [:]
            for j in s.profiles[i].addons.indices {
                s.profiles[i].addons[j].manifestURL = AddonAccess.publicManifestURL(s.profiles[i].addons[j].manifestURL)
            }
        }
        return s
    }
}
