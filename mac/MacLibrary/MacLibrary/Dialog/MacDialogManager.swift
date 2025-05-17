//
//  MacDialogManager.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import AppKit

public class MacDialogManager: NSObject {
    
    private let TAG = "MacDialogManager"
    
    public static let shared = MacDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    public func showDialog(title: String, message: String, handler: ((String) -> Void)?) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message), handler: \(String(describing: handler))")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Other")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                Log.d(self.TAG, "OK pressed")
                handler?("OK")
            case .alertSecondButtonReturn:
                Log.d(self.TAG, "Cancel pressed")
                handler?("Cancel")
            case .alertThirdButtonReturn:
                Log.d(self.TAG, "Other pressed")
                handler?("Other")
            default:
                Log.d(self.TAG, "Unknown button pressed")
                handler?("Unknown")
            }
        }
    }
}
