import CryptoKit
import Foundation

// Public-key verification also catches an accidentally configured CI secret.
let args = CommandLine.arguments
guard args.count == 4,
      let keyData = Data(base64Encoded: args[2]),
      let signature = Data(base64Encoded: args[3]) else {
    fputs("Invalid verification arguments\n", stderr)
    exit(1)
}
do {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    guard key.isValidSignature(signature, for: data) else {
        fputs("Update signature does not match the embedded public key\n", stderr)
        exit(1)
    }
} catch {
    fputs("Could not verify update signature\n", stderr)
    exit(1)
}
