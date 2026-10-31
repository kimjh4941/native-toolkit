// Hand-off 1 probe: UTF-8 in and out (part 1, 5.9).
import Foundation

enum CApiString {
    enum Input { case absent, value(String), invalid }

    /// Strict input (E-7): NULL is .absent, invalid UTF-8 is .invalid.
    static func input(_ pointer: UnsafePointer<CChar>?) -> Input {
        guard let pointer else { return .absent }
        guard let value = String(validatingCString: pointer) else { return .invalid }
        return .value(value)
    }

    /// Output (E-16 / AC-19): unpaired surrogates are repaired by Swift's String; U+0000 becomes U+FFFD.
    static func outputUTF8(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            bytes.append(contentsOf: UTF8.encode(scalar.value == 0 ? Unicode.Scalar(0xFFFD)! : scalar)!)
        }
        return bytes
    }
}
