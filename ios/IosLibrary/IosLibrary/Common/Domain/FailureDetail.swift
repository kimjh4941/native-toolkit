//
//  FailureDetail.swift
//  IosLibrary
//

import Foundation

/// The domain and code of a system error, kept in place of the error itself.
///
/// An error of the library that reports a failed system API carries a `FailureDetail`, so that
/// callers can tell the causes apart without the library keeping an arbitrary system `Error`. Only the
/// `NSError` domain and code are kept: the localized description is not, because its text
/// depends on the device language and can contain the values that were passed in.
///
/// ```swift
/// let detail = FailureDetail(systemError: error)
/// if detail.domain == NSCocoaErrorDomain, detail.code == NSFileNoSuchFileError {
///     // ...
/// }
/// ```
public struct FailureDetail: Sendable, Equatable {
    /// The `NSError` domain of the system error (for example `UNErrorDomain`).
    public let domain: String
    /// The `NSError` code of the system error.
    public let code: Int

    /// Creates a detail from a domain and a code.
    /// - Parameters:
    ///   - domain: The `NSError` domain.
    ///   - code: The `NSError` code.
    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }

    /// Creates a detail from a system error, keeping only its `NSError` domain and code.
    ///
    /// A Swift error that is not an `NSError` is bridged as Swift does it: its domain is the
    /// type name and its code is the `_code` of the error.
    /// - Parameter systemError: The error a system API reported.
    public init(systemError: any Error) {
        let nsError = systemError as NSError
        self.init(domain: nsError.domain, code: nsError.code)
    }
}
