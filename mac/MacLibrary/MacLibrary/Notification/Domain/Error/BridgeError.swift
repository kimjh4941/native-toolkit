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
public enum BridgeError: Error {
    /// JSON parsing failed.
    case parseFailed(reason: String)
    /// The bridge contract was violated (e.g., nil callback, unexpected nil argument).
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
