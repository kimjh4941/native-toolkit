//
//  UnityMacDialogManager.swift
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import AppKit
import MacLibrary

@objcMembers
public class UnityMacDialogManager: NSObject {
    
    private let TAG = "UnityMacDialogManager"
    
    public static let shared = UnityMacDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    public func showDialog(title: String, message: String, handler: ((String) -> Void)?) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message), handler: \(String(describing: handler))")
        MacDialogManager.shared.showDialog(title: title, message: message, handler: handler)
    }
}
