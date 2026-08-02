//
//  ClipboardMappers.swift
//  IosLibrary
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// Converts between `UIPasteboard` item dictionaries and Domain read-side types.
enum ClipboardMappers {
    /// Converts a single pasteboard item dictionary into `ClipboardItemData`.
    static func toItemData(_ item: [String: Any]) -> ClipboardItemData {
        let typeIdentifiers = Array(item.keys)
        var text: String?
        var urlString: String?
        var imageUTType: String?

        for (key, value) in item {
            if let type = UTType(key), type.conforms(to: .image) {
                imageUTType = imageUTType ?? key
                continue
            }
            if text == nil, let stringValue = value as? String {
                text = stringValue
            }
            if urlString == nil, let urlValue = value as? URL {
                urlString = urlValue.absoluteString
            }
        }

        return ClipboardItemData(
            typeIdentifiers: typeIdentifiers,
            text: text,
            urlString: urlString,
            imageDataUTType: imageUTType
        )
    }

    /// Builds the item dictionaries `setItems(_:options:)` / `addItems(_:)` expect.
    /// - Parameter encodedImage: Pre-encoded PNG data for `.imageFile` content (produced off the
    ///   main actor by `ClipboardImageCoder`); ignored for other content kinds.
    static func makeItems(from content: ClipboardContent, encodedImage: Data?) throws -> [[String: Any]] {
        switch content {
        case .plainText(let text):
            return [[UTType.plainText.identifier: text]]

        case .htmlText(let plain, let html):
            return [[UTType.plainText.identifier: plain, UTType.html.identifier: html]]

        case .url(let value):
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ClipboardError.invalidURL(value)
            }
            return [[UTType.url.identifier: url]]

        case .imageFile:
            guard let encodedImage else {
                throw ClipboardError.imageEncodingFailed
            }
            return [[UTType.png.identifier: encodedImage]]

        case .imageData(let data, let utType):
            return [[utType: data]]

        case .color(let red, let green, let blue, let alpha):
            let color = UIColor(red: red, green: green, blue: blue, alpha: alpha)
            // NOTE: verified against Apple's documented pasteboard representation type for
            // UIColor; treat as a要検証 (needs device verification) item during manual QA.
            return [[Self.colorTypeIdentifier: color]]

        case .customData(let data, let utType):
            return [[utType: data]]

        case .multipleText(let texts):
            return texts.map { [UTType.plainText.identifier: $0] }

        case .multiRepresentation(let representations):
            var item: [String: Any] = [:]
            for (key, value) in representations {
                item[key] = value
            }
            return [item]
        }
    }

    /// Registered type identifier `UIColor` uses for pasteboard item representation.
    static let colorTypeIdentifier = "com.apple.uikit.color"
}
