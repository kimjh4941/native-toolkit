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
    ///
    /// Representations are selected by uniform type identifier, never by dictionary iteration
    /// order: an item carrying both plain text and HTML always reports the *plain text* in `text`,
    /// and `urlString` always comes from a URL-conforming representation.
    static func toItemData(_ item: [String: Any]) -> ClipboardItemData {
        let typeIdentifiers = Array(item.keys)

        let text = firstValue(in: item, conformingTo: .plainText, as: String.self)
            ?? firstValue(in: item, conformingTo: .text, as: String.self)

        let urlString: String?
        if let url = firstValue(in: item, conformingTo: .url, as: URL.self) {
            urlString = url.absoluteString
        } else if let urlText = firstValue(in: item, conformingTo: .url, as: String.self) {
            urlString = urlText
        } else {
            urlString = nil
        }

        let imageUTType = typeIdentifiers
            .filter { UTType($0)?.conforms(to: .image) == true }
            .sorted()
            .first

        return ClipboardItemData(
            typeIdentifiers: typeIdentifiers,
            text: text,
            urlString: urlString,
            imageDataUTType: imageUTType
        )
    }

    /// Returns the value of the first representation (in stable identifier order) whose UTI
    /// conforms to `type` and whose value is of type `V`.
    private static func firstValue<V>(
        in item: [String: Any],
        conformingTo type: UTType,
        as valueType: V.Type
    ) -> V? {
        for key in item.keys.sorted() where UTType(key)?.conforms(to: type) == true {
            if let value = item[key] as? V { return value }
        }
        return nil
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
