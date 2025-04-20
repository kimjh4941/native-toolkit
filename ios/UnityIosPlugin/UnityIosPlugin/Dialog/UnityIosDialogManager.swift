//
//  IosDialogManager.swift
//  
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import UIKit
import IosLibrary

@objcMembers
public class UnityIosDialogManager: NSObject {
    
    private let TAG = "UnityIosDialogManager"
    
    public static let shared = UnityIosDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    public func showDialog(title: String, message: String, handler: ((String) -> Void)?) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message), handler: \(String(describing: handler))")
        let action = UIAlertAction(title: "OK", style: .default) { _ in
            Log.d(self.TAG, "OK button pressed")
            handler?("OK");
        }
        IosDialogManager.shared.showDialog(title: title, message: message, actions: [action])
    }
}
