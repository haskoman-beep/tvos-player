import CryptoKit
import Foundation
import PlayerCore

/// plan_nuvio_konto T1b: opens the Nuvio sign-in the phone page sealed (format and limits in
/// PlayerCore/Phone/PhoneSeal.swift): ChaChaPoly (ChaCha20-Poly1305, RFC 8439) with the session's page key.
/// Nil for a wrong key, changed bytes or a malformed box; PlayerCore then gives no command.
enum PhoneSealCryptoKit {
    static let open: PhoneSealOpen = { key, nonce, ciphertextAndTag, aad in
        guard key.count == PhoneSeal.keyLength, ciphertextAndTag.count >= PhoneSeal.tagLength,
              let n = try? ChaChaPoly.Nonce(data: nonce),
              let box = try? ChaChaPoly.SealedBox(nonce: n, ciphertext: ciphertextAndTag.dropLast(PhoneSeal.tagLength),
                                                  tag: ciphertextAndTag.suffix(PhoneSeal.tagLength)) else { return nil }
        return try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: aad)
    }
}
