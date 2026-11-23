import CryptoKit
import Foundation
import PlayerCore

/// Task 1.4: the real cipher of the encrypted backup (`player-sicherung.enc`, format in `PlayerCore/Store/BackupCrypto`).
/// Key: HKDF-SHA256 over the 6 digits of the code shown on the TV, with the random salt of the file and the fixed info
/// `BackupCrypto.hkdfInfo`, 32 bytes. Encryption: ChaChaPoly (ChaCha20-Poly1305), the file header as authenticated data.
struct CryptoKitBackupCipher: BackupCipher {
    private func key(_ code: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(code.utf8)), salt: salt,
                               info: BackupCrypto.hkdfInfo, outputByteCount: 32)
    }

    func seal(_ plaintext: Data, code: String, salt: Data, nonce: Data, header: Data) throws -> (ciphertext: Data, tag: Data) {
        let box = try ChaChaPoly.seal(plaintext, using: key(code, salt: salt), nonce: ChaChaPoly.Nonce(data: nonce),
                                      authenticating: header)
        return (box.ciphertext, box.tag)
    }

    func open(_ ciphertext: Data, tag: Data, code: String, salt: Data, nonce: Data, header: Data) throws -> Data {
        let box = try ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
        return try ChaChaPoly.open(box, using: key(code, salt: salt), authenticating: header)
    }
}
