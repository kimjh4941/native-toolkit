//
//  ShareEntry.swift
//  IosLibraryCApi
//

// The entry points of Share.h (C ABI design part 1, 5.3). Only @c @implementation functions; what they do is in
// ShareReceiver.swift and ShareHandles.swift.

@c @implementation
public func ntk_share_content_async(_ request: UnsafePointer<ntk_share_request>?, _ callback: ntk_share_result_fn?,
                                    _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_share_error {
    ShareReceiver.share(request, callback, userData, release)
}

@c @implementation
public func ntk_share_result_completed(_ result: OpaquePointer?) -> Int32 {
    ShareHandles.completed(result)
}

@c @implementation
public func ntk_share_result_activity_type(_ result: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    ShareHandles.activityType(result, outSize)
}

@c @implementation
public func ntk_share_result_free(_ result: OpaquePointer?) {
    Handle.free(result)
}
