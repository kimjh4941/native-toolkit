//
//  IosDialogManager.swift
//  
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
import UIKit

public class IosDialogManager: NSObject {
    
    private let TAG = "IosDialogManager"
    
    public static let shared = IosDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    public func showDialog(title: String, message: String, actions: [UIAlertAction]) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message), actions: \(actions.map { $0.title ?? "nil" })")
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            for action in actions {
                alert.addAction(action)
            }
            
            if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
                rootViewController.present(alert, animated: true, completion: nil)
            }
        }
    }
}
