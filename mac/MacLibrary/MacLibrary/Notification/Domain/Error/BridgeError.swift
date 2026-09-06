//
//  BridgeError.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// Errors that occur at the C Bridge / JSON parsing boundary.
///
/// Use `errorCode` and `errorMessage` for the bridge return contract
/// `(isSuccess: Bool, errorCode: Int, errorMessage: String?)`.
///
/// ## NULL callbacks
///
/// A NULL operation callback is **not** an error by itself. A caller that does not need the
/// result should still be able to perform the operation, so the work runs and nothing is
/// reported back.
///
/// Two narrow exceptions exist, and both are about a result the caller cannot do without:
///
/// - An endpoint that creates a resource whose result is the only way to release it —
///   a unique pasteboard — does nothing at all when its callback is NULL, because the
///   resource would otherwise be created and immediately unreachable.
/// - An endpoint whose entire purpose is to deliver events reports ``contractViolation(reason:)``
///   when its **event** callback is NULL, since the subscription would produce no observable
///   result.
public enum BridgeError: Error {
    /// JSON parsing failed.
    case parseFailed(reason: String)
    /// The bridge contract was violated.
    ///
    /// Raised for a missing or unusable argument, and for a NULL **event** callback on an
    /// endpoint that exists to deliver events. A NULL **operation** callback is not a
    /// violation; see the type's discussion above.
    case contractViolation(reason: String)

    /// Numeric error code used in the C Bridge return contract.
    public var errorCode: Int {
        switch self {
        case .parseFailed:        return 1301
        case .contractViolation:  return 1302
        }
    }

    /// Human-readable error message used in the C Bridge return contract.
    public var errorMessage: String {
        switch self {
        case .parseFailed(let reason):
            return "Failed to parse JSON: \(reason)"
        case .contractViolation(let reason):
            return "Bridge contract violation: \(reason)"
        }
    }
}
