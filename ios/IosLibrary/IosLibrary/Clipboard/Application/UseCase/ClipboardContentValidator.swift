//
//  ClipboardContentValidator.swift
//  IosLibrary
//

import Foundation

/// Pure, platform-independent validation of `ClipboardContent`, runnable on any thread.
///
/// Size accounting for `imageFile` requires filesystem / decode access and is therefore performed
/// by the Data layer (`ClipboardRepositoryImpl` / `ClipboardImageCoder`), not here.
public struct ClipboardContentValidator: Sendable {
    private let clock: ClipboardClock
    private let limits: ClipboardLimits

    public init(clock: ClipboardClock = SystemClock(), limits: ClipboardLimits = .default) {
        self.clock = clock
        self.limits = limits
    }

    /// Validates `content` for a `copy` or `append` operation.
    public func validate(_ content: ClipboardContent) throws {
        switch content {
        case .plainText(let text):
            try checkByteCount(utf8ByteCount(text))

        case .htmlText(let plain, let html):
            guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClipboardError.emptyContent
            }
            try checkByteCount(utf8ByteCount(plain), utf8ByteCount(html))

        case .url(let value):
            try validateURL(value)

        case .imageFile(let path):
            guard !path.isEmpty else {
                throw ClipboardError.invalidRequest("imageFile path must not be empty")
            }

        case .imageData(let data, _):
            guard !data.isEmpty else { throw ClipboardError.emptyContent }
            try checkByteCount(data.count)

        case .color(let red, let green, let blue, let alpha):
            try validateColor(red: red, green: green, blue: blue, alpha: alpha)
            try checkByteCount(32)

        case .customData(let data, _):
            guard !data.isEmpty else { throw ClipboardError.emptyContent }
            try checkByteCount(data.count)

        case .multipleText(let texts):
            guard !texts.isEmpty else { throw ClipboardError.emptyItemList }
            try checkByteCount(texts.map(utf8ByteCount))

        case .multiRepresentation(let representations):
            guard !representations.isEmpty else { throw ClipboardError.emptyItemList }
            var total = 0
            for (key, value) in representations {
                guard !key.isEmpty else {
                    throw ClipboardError.invalidTypeIdentifier(key)
                }
                guard !value.isEmpty else { throw ClipboardError.emptyContent }
                total = try add(total, utf8ByteCount(key))
                total = try add(total, value.count)
            }
            try checkByteCount(total)
        }
    }

    /// Validates `expirationDate` against the injected clock.
    public func validateExpirationDate(_ date: Date?) throws {
        guard let date else { return }
        guard date > clock.now() else {
            throw ClipboardError.invalidExpirationDate
        }
    }

    private func validateURL(_ string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            throw ClipboardError.invalidURL(string)
        }
        switch scheme {
        case "http", "https":
            guard let host = url.host, !host.isEmpty else {
                throw ClipboardError.invalidURL(string)
            }
        case "file":
            guard url.isFileURL else {
                throw ClipboardError.invalidURL(string)
            }
        default:
            throw ClipboardError.invalidURL(string)
        }
    }

    private func validateColor(red: Double, green: Double, blue: Double, alpha: Double) throws {
        for component in [red, green, blue, alpha] {
            guard component.isFinite, (0.0...1.0).contains(component) else {
                throw ClipboardError.invalidColor
            }
        }
    }

    private func utf8ByteCount(_ string: String) -> Int { string.utf8.count }

    private func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw ClipboardError.contentTooLarge(byteCount: Int.max, limit: limits.maxCopyByteCount)
        }
        return result
    }

    private func checkByteCount(_ counts: Int...) throws {
        try checkByteCount(counts)
    }

    private func checkByteCount(_ counts: [Int]) throws {
        var total = 0
        for count in counts {
            total = try add(total, count)
        }
        guard total <= limits.maxCopyByteCount else {
            throw ClipboardError.contentTooLarge(byteCount: total, limit: limits.maxCopyByteCount)
        }
    }
}
