//
//  DialogReceiver.swift
//  IosLibraryCApi
//

import IosLibrary

/// What the functions of Dialog.h do. They come with TB-5; this is what the shared parts take from Dialog.
enum DialogReceiver {
    /// A Dialog request closes its box through the manager (part 2, 5.3; OP-24).
    static let cancelKind = CancellableKind(name: "dialog") { IosDialogManager.shared.cancel($0) }
}
