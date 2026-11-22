//
//  ClipboardEntry.swift
//  IosLibraryCApi
//

// The entry points of Clipboard.h (C ABI design part 1, 5.3). Only @c @implementation functions, whose
// types the compiler checks against the header; what they do is in ClipboardReceiver.swift and
// ClipboardHandles.swift.

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

@c @implementation
public func ntk_clipboard_load_item_async(_ kind: ntk_clipboard_item_kind, _ utType: UnsafePointer<CChar>?, _ scope: UnsafePointer<ntk_clipboard_scope>?,
                                          _ callback: ntk_clipboard_load_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                          _ outRequestID: UnsafeMutablePointer<UInt64>?) -> ntk_clipboard_error {
    ClipboardReceiver.loadItem(kind, utType, scope, callback, userData, release, outRequestID)
}

@c @implementation
public func ntk_clipboard_cancel_load(_ requestID: UInt64) -> ntk_clipboard_error {
    ClipboardReceiver.cancelLoad(requestID)
}

@c @implementation
public func ntk_clipboard_start_observing_async(_ scope: UnsafePointer<ntk_clipboard_scope>?, _ callback: ntk_clipboard_done_fn?,
                                                _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.startObserving(scope, callback, userData, release)
}

@c @implementation
public func ntk_clipboard_stop_observing_async(_ callback: ntk_clipboard_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                               _ release: ntk_release_fn?) -> ntk_clipboard_error {
    ClipboardReceiver.stopObserving(callback, userData, release)
}

@c @implementation
public func ntk_clipboard_add_change_listener(_ callback: ntk_clipboard_change_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                              _ outListener: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_clipboard_error {
    ClipboardReceiver.addChangeListener(callback, userData, release, outListener)
}

@c @implementation
public func ntk_clipboard_listener_remove(_ listener: OpaquePointer?) {
    ClipboardReceiver.removeListener(listener)
}

@c @implementation
public func ntk_clipboard_loaded_item_kind(_ item: OpaquePointer?) -> ntk_clipboard_item_kind {
    ClipboardHandles.loadedItemKind(item)
}

@c @implementation
public func ntk_clipboard_loaded_item_text(_ item: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.loadedItemText(item, outSize)
}

@c @implementation
public func ntk_clipboard_loaded_item_url(_ item: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.loadedItemUrl(item, outSize)
}

@c @implementation
public func ntk_clipboard_loaded_item_image_data(_ item: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>? {
    ClipboardHandles.loadedItemImageData(item, outSize)
}

@c @implementation
public func ntk_clipboard_loaded_item_image_type(_ item: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.loadedItemImageType(item, outSize)
}

@c @implementation
public func ntk_clipboard_loaded_item_file_path(_ item: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.loadedItemFilePath(item, outSize)
}

@c @implementation
public func ntk_clipboard_loaded_item_free(_ item: OpaquePointer?) {
    Handle.free(item)
}

@c @implementation
public func ntk_clipboard_change_kind(_ change: OpaquePointer?) -> ntk_clipboard_change_event_kind {
    ClipboardHandles.changeKind(change)
}

@c @implementation
public func ntk_clipboard_change_scope_kind(_ change: OpaquePointer?) -> ntk_clipboard_scope_kind {
    ClipboardHandles.changeScopeKind(change)
}

@c @implementation
public func ntk_clipboard_change_scope_name(_ change: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.changeScopeName(change, outSize)
}

@c @implementation
public func ntk_clipboard_change_types_added_count(_ change: OpaquePointer?) -> Int {
    ClipboardHandles.changeTypesAddedCount(change)
}

@c @implementation
public func ntk_clipboard_change_types_added_at(_ change: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.changeTypesAddedAt(change, index, outSize)
}

@c @implementation
public func ntk_clipboard_change_types_removed_count(_ change: OpaquePointer?) -> Int {
    ClipboardHandles.changeTypesRemovedCount(change)
}

@c @implementation
public func ntk_clipboard_change_types_removed_at(_ change: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ClipboardHandles.changeTypesRemovedAt(change, index, outSize)
}

@c @implementation
public func ntk_clipboard_change_free(_ change: OpaquePointer?) {
    Handle.free(change)
}
