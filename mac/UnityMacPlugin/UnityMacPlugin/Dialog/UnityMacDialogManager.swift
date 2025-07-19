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
    
    public func showDialog(
        title: String,
        message: String,
        buttonsJson: String,
        optionsJson: String,
        completion: @escaping (NSDictionary?, NSError?) -> Void
    ) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message)")
        // Parse buttonsJson
        var buttons: [DialogButton] = []
        if let buttonsData = buttonsJson.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: buttonsData) as? [String: Any],
           let buttonsArray = jsonObject["buttons"] as? [[String: Any]] {
            for buttonDict in buttonsArray {
                if let title = buttonDict["title"] as? String {
                    let isDefault = buttonDict["isDefault"] as? Bool ?? false
                    let keyEquivalent = buttonDict["keyEquivalent"] as? String ?? ""
                    let button = DialogButton(title: title, isDefault: isDefault, keyEquivalent: keyEquivalent)
                    buttons.append(button)
                }
            }
        }
        
        // Parse optionsJson
        var options = DialogOptions()
        if let optionsData = optionsJson.data(using: .utf8),
           let optionsDict = try? JSONSerialization.jsonObject(with: optionsData) as? [String: Any] {
            
            if let alertStyleString = optionsDict["alertStyle"] as? String {
                switch alertStyleString {
                case "warning":
                    options.alertStyle = .warning
                case "informational":
                    options.alertStyle = .informational
                case "critical":
                    options.alertStyle = .critical
                default:
                    options.alertStyle = .informational
                }
            }
            
            if let showsSuppressionButton = optionsDict["showsSuppressionButton"] as? Bool {
                options.showsSuppressionButton = showsSuppressionButton
            }
            
            if let suppressionButtonTitle = optionsDict["suppressionButtonTitle"] as? String {
                options.suppressionButtonTitle = suppressionButtonTitle
            }
        }
        
        // Set buttons to options
        options.buttons = buttons
        
        MacDialogManager.shared.showDialog(title: title, message: message, options: options) { result in
            switch result {
            case .success(let dialogResult):
                // Convert DialogResult to NSDictionary
                let resultDict: NSDictionary = [
                    "buttonTitle": dialogResult.buttonTitle,
                    "buttonIndex": dialogResult.buttonIndex,
                    "suppressionButtonState": dialogResult.suppressionButtonState
                ]
                completion(resultDict, nil)
            case .failure(let error):
                // Convert DialogError to NSError
                let nsError = NSError(domain: "DialogError", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion(nil, nsError)
            }
        }
    }
    
    public func showFileDialog(
        title: String,
        message: String,
        allowedContentTypes: [String],
        directoryURL: URL?,
        completion: @escaping (NSDictionary?, NSError?) -> Void
    ) {
        Log.d(TAG, "showFileDialog called with title: \(title)")

        MacDialogManager.shared.showFileDialog(
            title: title,
            message: message,
            allowedContentTypes: allowedContentTypes,
            directoryURL: directoryURL
        ) { result in
            switch result {
            case .success(let openResult):
                let resultDict: NSDictionary = [
                    "filePaths": openResult.filePaths,
                    "fileCount": openResult.fileCount,
                    "directoryURL": openResult.directoryURL,
                    "isCancelled": openResult.isCancelled,
                    "isSuccess": openResult.isSuccess
                ]
                completion(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion(nil, nsError)
            }
        }
    }
    
    public func showMultiFileDialog(
        title: String,
        message: String,
        allowedContentTypes: [String],
        directoryURL: URL?,
        completion: @escaping (NSDictionary?, NSError?) -> Void
    ) {
        Log.d(TAG, "showMultiFileDialog called with title: \(title)")
        
        MacDialogManager.shared.showMultiFileDialog(
            title: title,
            message: message,
            allowedContentTypes: allowedContentTypes,
            directoryURL: directoryURL
        ) { result in
            switch result {
            case .success(let openResult):
                let resultDict: NSDictionary = [
                    "filePaths": openResult.filePaths,
                    "fileCount": openResult.fileCount,
                    "directoryURL": openResult.directoryURL,
                    "isCancelled": openResult.isCancelled,
                    "isSuccess": openResult.isSuccess
                ]
                completion(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion(nil, nsError)
            }
        }
    }
    
    public func showFolderDialog(
        title: String,
        message: String,
        directoryURL: URL?,
        completion: @escaping (NSDictionary?, NSError?) -> Void
    ) {
        Log.d(TAG, "showFolderDialog called with title: \(title)")

        MacDialogManager.shared.showFolderDialog(
            title: title,
            message: message,
            directoryURL: directoryURL
        ) { result in
            switch result {
            case .success(let openResult):
                let resultDict: NSDictionary = [
                    "filePaths": openResult.filePaths,
                    "fileCount": openResult.fileCount,
                    "directoryURL": openResult.directoryURL,
                    "isCancelled": openResult.isCancelled,
                    "isSuccess": openResult.isSuccess
                ]
                completion(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 2, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion(nil, nsError)
            }
        }
    }
    
    public func showMultiFolderDialog(
        title: String,
        message: String,
        directoryURL: URL?,
        completion: @escaping (NSDictionary?, NSError?) -> Void
    ) {
        Log.d(TAG, "showMultiFolderDialog called with title: \(title)")

        MacDialogManager.shared.showMultiFolderDialog(
            title: title,
            message: message,
            directoryURL: directoryURL
        ) { result in
            switch result {
            case .success(let openResult):
                let resultDict: NSDictionary = [
                    "filePaths": openResult.filePaths,
                    "fileCount": openResult.fileCount,
                    "directoryURL": openResult.directoryURL,
                    "isCancelled": openResult.isCancelled,
                    "isSuccess": openResult.isSuccess
                ]
                completion(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 2, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion(nil, nsError)
            }
        }
    }
    
    public func showSaveFileDialog(
        title: String,
        message: String,
        nameFieldStringValue: String,
        allowedContentTypes: [String],
        directoryURL: URL?,
        completion: @escaping (NSDictionary?, NSError?) -> Void
    ) {
        Log.d(TAG, "showSaveFileDialog called with title: \(title)")

        MacDialogManager.shared.showSaveFileDialog(
            title: title,
            message: message,
            nameFieldStringValue: nameFieldStringValue,
            allowedContentTypes: allowedContentTypes,
            directoryURL: directoryURL
        ) { result in
            switch result {
            case .success(let saveResult):
                let resultDict: NSDictionary = [
                    "filePath": saveResult.filePath,
                    "fileCount": saveResult.fileCount,
                    "directoryURL": saveResult.directoryURL,
                    "isCancelled": saveResult.isCancelled,
                    "isSuccess": saveResult.isSuccess
                ]
                completion(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 3, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion(nil, nsError)
            }
        }
    }
}
