//
//  ShareHandles.swift
//  IosLibraryCApi
//

/// What an `ntk_share_result*` points to.
final class ShareResultHandle {
    let completed: Bool
    let activityType: HandleBuffer?

    init(_ value: ShareResultValue) {
        completed = value.completed
        activityType = value.activityType.map { HandleBuffer(CApiString.outputUTF8($0)) }
    }
}

/// The readers of the result. NULL and a handle of another type read as nothing: 0 and NULL with an `out_size` of 0.
/// Reads and frees are not logged (part 1, 5.15).
enum ShareHandles {
    static func makeResult(_ value: ShareResultValue) -> OpaquePointer {
        CApiLog.share.debug("[makeResult] completed: \(value.completed, privacy: .public)")
        return Handle.retained(ShareResultHandle(value))
    }

    private static func result(_ handle: OpaquePointer?) -> ShareResultHandle? {
        Handle.borrow(handle, as: ShareResultHandle.self)
    }

    static func completed(_ handle: OpaquePointer?) -> Int32 {
        result(handle)?.completed == true ? 1 : 0
    }

    static func activityType(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: result(handle)?.activityType, outSize)
    }
}
