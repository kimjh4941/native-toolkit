// Fallback layout (stage 1a): fills the table of Swift receivers. The receivers are the same
// as in the @c @implementation layout (Support.swift, ProbeImpl.swift); only the entry differs.
import Foundation
internal import NTKCApiFallbackInternal

/// Found by name through the Objective-C runtime from Entry.c, so the class name must be unique
/// in the process (D-11 (2)): hence the NTKCApi prefix.
@objc(NTKCApiFallbackInstaller)
final class FallbackInstaller: NSObject {
    /// Allocated once and never freed, so that the address handed to C stays valid.
    private nonisolated(unsafe) static let table: UnsafeMutablePointer<ntkc_table> = {
        let table = UnsafeMutablePointer<ntkc_table>.allocate(capacity: 1)
        table.initialize(to: ntkc_table(
            struct_size: UInt32(MemoryLayout<ntkc_table>.size), reserved0: 0,
            string_data: { Receivers.stringData($0) },
            string_size: { Receivers.stringSize($0) },
            string_free: { Handle.free($0) },
            bytes_data: { Receivers.bytesData($0) },
            bytes_size: { Receivers.stringSize($0) },
            bytes_free: { Handle.free($0) },
            string_list_count: { Receivers.listCount($0) },
            string_list_at: { Receivers.listAt($0, $1, $2) },
            string_list_free: { Handle.free($0) },
            probe_echo: { ProbeImpl.echo($0, $1) },
            probe_clipboard_read_text_async: { ProbeImpl.clipboardReadTextAsync($0, $1, $2, $3) },
            probe_raise_uikit_exception_async: { ProbeImpl.raiseUIKitExceptionAsync($0, $1, $2, $3, $4) }))
        return table
    }()

    @objc static func install() {
        ntkc_register(table)
    }
}
