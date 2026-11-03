//
//  ClipboardEntry.swift
//  IosLibraryCApi
//

// The entry points of Clipboard.h (C ABI design part 1, 5.3). Only @c @implementation functions, whose
// types the compiler checks against the header; what they do is in ClipboardReceiver.swift and
// ClipboardHandles.swift. The load and the observation come with TB-4.

@c @implementation
public func ntk_clipboard_copy_async(_ content: UnsafePointer<ntk_clipboard_write_content>?, _ options: UnsafePointer<ntk_clipboard_copy_options>?,
                                     _ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                                     _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.copy(content, options, scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_append_async(_ content: UnsafePointer<ntk_clipboard_write_content>?, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                                       _ callback: ntk_clipboard_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                       _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.append(content, scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_read_async(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_read_fn?,
                                     _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.read(scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_read_data_async(_ utType: UnsafePointer<CChar>?, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                                          _ callback: ntk_clipboard_data_fn?, _ userData: UnsafeMutableRawPointer?,
                                          _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.readData(utType, scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_get_snapshot_async(_ matchingTypes: UnsafePointer<UnsafePointer<CChar>?>?, _ matchingTypeCount: Int,
                                             _ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_snapshot_fn?,
                                             _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.snapshot(matchingTypes, matchingTypeCount, scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_clear_async(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                                      _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.clear(scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_create_pasteboard_async(_ kind: ntk_clipboard_scope_kind, _ name: UnsafePointer<CChar>?, _ callback: ntk_clipboard_name_fn?,
                                                  _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.createPasteboard(kind, name, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_remove_pasteboard_async(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                                                  _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.removePasteboard(scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_detect_patterns_async(_ patterns: ntk_clipboard_patterns, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                                                _ callback: ntk_clipboard_patterns_fn?, _ userData: UnsafeMutableRawPointer?,
                                                _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.detectPatterns(patterns, scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_detect_values_async(_ patterns: ntk_clipboard_patterns, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                                              _ callback: ntk_clipboard_values_fn?, _ userData: UnsafeMutableRawPointer?,
                                              _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.detectValues(patterns, scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_check_foreground_change_async(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_foreground_change_fn?,
                                                        _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.checkForegroundChange(scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_read_result_item_count(_ result: OpaquePointer?) -> Int {
    ClipboardHandles.readResultItemCount(result)
}

@c @implementation
public func ntk_clipboard_read_result_item_type_count(_ result: OpaquePointer?, _ item: Int) -> Int {
    ClipboardHandles.readResultItemTypeCount(result, item)
}

@c @implementation
public func ntk_clipboard_read_result_item_type_at(_ result: OpaquePointer?, _ item: Int, _ index: Int,
                                                   _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.readResultItemTypeAt(result, item, index, outSize)
}

@c @implementation
public func ntk_clipboard_read_result_item_text_at(_ result: OpaquePointer?, _ item: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.readResultItemTextAt(result, item, outSize)
}

@c @implementation
public func ntk_clipboard_read_result_item_url_at(_ result: OpaquePointer?, _ item: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.readResultItemUrlAt(result, item, outSize)
}

@c @implementation
public func ntk_clipboard_read_result_item_image_type_at(_ result: OpaquePointer?, _ item: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.readResultItemImageTypeAt(result, item, outSize)
}

@c @implementation
public func ntk_clipboard_read_result_free(_ result: OpaquePointer?) {
    Handle.free(result)
}

@c @implementation
public func ntk_clipboard_snapshot_has_strings(_ snapshot: OpaquePointer?) -> Int32 {
    ClipboardHandles.snapshotHasStrings(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_has_urls(_ snapshot: OpaquePointer?) -> Int32 {
    ClipboardHandles.snapshotHasUrls(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_has_images(_ snapshot: OpaquePointer?) -> Int32 {
    ClipboardHandles.snapshotHasImages(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_has_colors(_ snapshot: OpaquePointer?) -> Int32 {
    ClipboardHandles.snapshotHasColors(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_number_of_items(_ snapshot: OpaquePointer?) -> Int {
    ClipboardHandles.snapshotNumberOfItems(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_type_count(_ snapshot: OpaquePointer?) -> Int {
    ClipboardHandles.snapshotTypeCount(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_type_at(_ snapshot: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.snapshotTypeAt(snapshot, index, outSize)
}

@c @implementation
public func ntk_clipboard_snapshot_item_type_count(_ snapshot: OpaquePointer?, _ item: Int) -> Int {
    ClipboardHandles.snapshotItemTypeCount(snapshot, item)
}

@c @implementation
public func ntk_clipboard_snapshot_item_type_at(_ snapshot: OpaquePointer?, _ item: Int, _ index: Int,
                                                _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.snapshotItemTypeAt(snapshot, item, index, outSize)
}

@c @implementation
public func ntk_clipboard_snapshot_has_matching(_ snapshot: OpaquePointer?) -> Int32 {
    ClipboardHandles.snapshotHasMatching(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_matching_count(_ snapshot: OpaquePointer?) -> Int {
    ClipboardHandles.snapshotMatchingCount(snapshot)
}

@c @implementation
public func ntk_clipboard_snapshot_matching_at(_ snapshot: OpaquePointer?, _ index: Int) -> Int64 {
    ClipboardHandles.snapshotMatchingAt(snapshot, index)
}

@c @implementation
public func ntk_clipboard_snapshot_free(_ snapshot: OpaquePointer?) {
    Handle.free(snapshot)
}
