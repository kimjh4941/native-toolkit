//
//  ShareItemSource.swift
//  IosLibrary
//

import UIKit
import LinkPresentation

/// Wraps a single primary share item, supplying subject and rich link metadata.
///
/// This REPLACES the primary item in the activity items array (it is not an additional
/// sidecar item), so the content is never shared twice. `activityViewControllerPlaceholderItem`
/// and `activityViewController(_:itemForActivityType:)` both return the same primary item.
final class ShareItemSource: NSObject, UIActivityItemSource {

    private let primaryItem: Any
    private let subject: String?
    private let previewTitle: String?

    /// Creates an item source wrapping a single primary item.
    /// - Parameters:
    ///   - primaryItem: The activation item to present (e.g. `String`, `URL`, or `UIImage`).
    ///   - subject: Optional subject for activities that support it (e.g. Mail).
    ///   - previewTitle: Optional title used to build immediate `LPLinkMetadata` preview.
    init(primaryItem: Any, subject: String?, previewTitle: String?) {
        self.primaryItem = primaryItem
        self.subject = subject
        self.previewTitle = previewTitle
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        primaryItem
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        primaryItem
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        subject ?? ""
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        guard let previewTitle else { return nil }
        let metadata = LPLinkMetadata()
        metadata.title = previewTitle
        if let url = primaryItem as? URL {
            metadata.originalURL = url
        }
        return metadata
    }
}
