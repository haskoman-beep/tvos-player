import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// plan_nuvio_konto T1b: the Nuvio e-mail and password cross the Wi-Fi only sealed.
//
// How: when the TV makes a phone session it also makes a random 32-byte page key (`PhoneSession.pageKey`). The QR
// address carries it in the URL fragment (`#nuvio&k=<base64url>` or `#k=<base64url>`), which a browser never sends in
// a request. The page script (`PhoneSealScript`) moves it to sessionStorage, seals {"email","password"} with
// ChaCha20-Poly1305 (RFC 8439, random 12-byte nonce, additional data `PhoneSeal.label`) and posts only
// `sealed=<base64url(nonce || ciphertext || tag)>`. The JSON carries a third member "pad" (spaces) so it is exactly
// `paddingBlock` bytes, or the next multiple of it for long fields; the envelope size then does not tell the password
// length. The TV opens it with the injected `PhoneSealOpen` (`PhoneSeal.cryptoKitOpen` in the app), accepts each
// nonce once per session, ignores "pad", and refuses the e-mail or password in clear. The page drops the key once the
// sign-in went to the TV (`nv=gesendet`) and on the "no access" page; a key in a request's address ends the session.
//
// Honest limits: this protects against someone who only listens on the Wi-Fi. It does not protect against someone who
// can alter traffic on the LAN (they can change the page script itself, which comes over plain HTTP), nor against a
// compromised phone or TV. The key is as secret as the QR code on the TV screen and the phone's browser. The full QR
// address, key included, may remain in the phone browser's history or in a QR scanner app's scan log; someone who
// recorded the Wi-Fi traffic and later obtains that history or log can open the recorded sign-in. There is no forward
// secrecy: the key is fixed per session and nothing is agreed on the fly.

/// Opens a ChaCha20-Poly1305 box (RFC 8439): 32-byte key, 12-byte nonce, ciphertext followed by its 16-byte tag, and
/// the additional data. Nil if the tag does not match. Linux has no CryptoKit, so the opener is injected; the app passes
/// `PhoneSeal.cryptoKitOpen`.
public typealias PhoneSealOpen = @Sendable (_ key: Data, _ nonce: Data, _ ciphertextAndTag: Data, _ aad: Data) -> Data?

#if canImport(CryptoKit)
extension PhoneSeal {
    /// The opener the app ships: CryptoKit ChaChaPoly (ChaCha20-Poly1305, RFC 8439). Nil for a wrong key or additional
    /// data, changed bytes or a malformed box; PlayerCore then gives no command. Tested against the JavaScript fixture
    /// in `javaScriptFixtureOpensWithCryptoKit` (macOS CI job).
    public static let cryptoKitOpen: PhoneSealOpen = { key, nonce, ciphertextAndTag, aad in
        guard key.count == keyLength, nonce.count == nonceLength, ciphertextAndTag.count >= tagLength,
              let n = try? ChaChaPoly.Nonce(data: nonce),
              let box = try? ChaChaPoly.SealedBox(nonce: n, ciphertext: ciphertextAndTag.dropLast(tagLength),
                                                  tag: ciphertextAndTag.suffix(tagLength)) else { return nil }
        return try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: aad)
    }
}
#endif

/// The Nuvio sign-in after opening; both values stay wrapped (`PhoneSecret`).
public struct PhoneNuvioLogin: Equatable, Sendable {
    public let email: PhoneSecret
    public let password: PhoneSecret
    public init(email: PhoneSecret, password: PhoneSecret) { self.email = email; self.password = password }
}

public enum PhoneSeal {
    /// Additional data of the sign-in box (ASCII); a new format gets a new label.
    public static let label = "player-nuvio-login-v1"
    public static var aad: Data { Data(label.utf8) }
    /// The only form field `POST /nuvio` accepts.
    public static let fieldName = "sealed"
    public static let keyLength = 32
    public static let nonceLength = 12
    public static let tagLength = 16
    /// The page pads the sealed JSON to a multiple of this many bytes (`PAD_BLOCK` in `PhoneSealScript`).
    public static let paddingBlock = 1024
    /// Longest accepted `sealed` field (base64url characters): whatever fits the body limit of `POST /nuvio`, so every
    /// sign-in that arrives is opened and gets the field rules (`nv=leer` when too long) instead of `nv=krypto`. The
    /// largest allowed one (two 256-byte fields as escaped JSON, padded to 4096 bytes) needs 5499 characters.
    static let maxFieldLength = PhoneLimits.maxBody(for: PhoneInputPage.nuvioPath) - (fieldName.utf8.count + 1)
    /// On the phone when the script cannot seal or the TV cannot open (redirect note `nv=krypto`).
    public static let failureText = "Verschlüsselung nicht möglich. Bitte den QR-Code am Fernseher neu scannen."

    public struct Envelope: Equatable, Sendable {
        public let nonce: Data
        public let ciphertextAndTag: Data
    }

    /// Splits the `sealed` field. Strict base64url without padding; nil for anything else or a box shorter than a tag.
    public static func envelope(_ field: String) -> Envelope? {
        guard field.utf8.count <= maxFieldLength, let raw = fromBase64URL(field), raw.count >= nonceLength + tagLength else { return nil }
        return Envelope(nonce: Data(raw.prefix(nonceLength)), ciphertextAndTag: Data(raw.dropFirst(nonceLength)))
    }

    /// The opened plaintext: a JSON object with the strings `email` and `password`.
    static func login(fromJSON data: Data) -> PhoneNuvioLogin? {
        struct Body: Decodable { let email: String; let password: String }
        guard let b = try? JSONDecoder().decode(Body.self, from: data) else { return nil }
        return PhoneNuvioLogin(email: PhoneSecret(b.email), password: PhoneSecret(b.password))
    }

    /// Fragment of the QR address: the section anchor (if any), then the key. The page script reads `k` and leaves the
    /// anchor in the address.
    static func fragment(section: PhoneSection?, key: Data) -> String {
        (section.map { $0.rawValue + "&" } ?? "") + "k=" + base64URL(key)
    }

    public static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromBase64URL(_ s: String) -> Data? {
        guard s.utf8.allSatisfy({ c in
            (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F
        }), s.utf8.count % 4 != 1 else { return nil }
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.utf8.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }
}

/// The page key inside `PhoneSession`: printing, debug printing and reflection never show it.
struct PhonePageKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let data: Data
    var description: String { PhoneSecret.masked }
    var debugDescription: String { PhoneSecret.masked }
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

extension PhoneSession {
    public static func randomPageKey() -> Data {
        var g = SystemRandomNumberGenerator()
        return Data((0..<PhoneSeal.keyLength).map { _ in UInt8.random(in: .min ... .max, using: &g) })
    }

    /// The page key; only for building the QR address and opening. Never part of a response, header or log.
    var pageKey: Data { key.data }

    /// QR address: one-time token in the query, section anchor and page key in the fragment.
    /// `base` is `http://<address>:<port>` without a slash at the end.
    public func qrAddress(base: String, section: PhoneSection?) -> String {
        "\(base)/?t=\(token)#\(PhoneSeal.fragment(section: section, key: key.data))"
    }

    /// Opens the `sealed` field of `POST /nuvio` with this session's key. Nil (no command) without an opener, before
    /// the QR address was used, after the session ended, for a nonce this session already accepted, when the box does
    /// not open, or when the plaintext is not the sign-in JSON. A nonce counts as used once its box opened.
    public mutating func openNuvioLogin(_ field: String, open: PhoneSealOpen?) -> PhoneNuvioLogin? {
        guard let open, tokenUsed, !ended, let env = PhoneSeal.envelope(field), !usedNonces.contains(env.nonce),
              let plain = open(key.data, env.nonce, env.ciphertextAndTag, PhoneSeal.aad) else { return nil }
        usedNonces.insert(env.nonce)
        return PhoneSeal.login(fromJSON: plain)
    }
}
