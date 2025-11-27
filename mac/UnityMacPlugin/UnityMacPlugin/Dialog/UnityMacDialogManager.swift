//
//  UnityMacDialogManager.swift
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import AppKit
import MacLibrary

@objcMembers
/// Bridges macOS dialog functionality (alerts, file/folder pickers, save panels)
/// to Unity / C callers through Objective‑C compatible signatures.
///
/// This manager converts Swift `Result` based APIs from `MacDialogManager` into
/// Objective‑C friendly `(NSDictionary?, NSError?)` callbacks so they can be
/// marshalled across the C bridge layer into Unity.
///
/// - Thread Safety: Public APIs internally dispatch UI work onto the main thread
///   (handled by `MacDialogManager`). You can call these methods from any thread.
/// - Returned Dictionary Keys:
///   - Alert (`showDialog`): `buttonTitle`, `buttonIndex`, `suppressionButtonState`
///   - Open / File / MultiFile / Folder / MultiFolder: `filePaths` (Array<String>),
///     `fileCount` (Int), `directoryURL` (String), `isCancelled` (Bool), `isSuccess` (Bool)
///   - Save: `filePath` (String), `fileCount` (Int), `directoryURL` (String),
///     `isCancelled` (Bool), `isSuccess` (Bool)
///
/// - Note: All error paths deliver an `NSError` whose `localizedDescription` derives
///   from `DialogError.localizedDescription`.
public class UnityMacDialogManager: NSObject {
    
    private let TAG = "UnityMacDialogManager"
    
    public static let shared = UnityMacDialogManager()
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }
    
    /// Presents an `NSAlert` configured via JSON button/option payloads and bridges the result
    /// back to Objective-C/Unity as `(NSDictionary?, NSError?)`.
    ///
    /// Expected JSON payloads:
    /// ```json
    /// // buttonsJson
    /// {
    ///   "buttons": [
    ///     { "title": "OK", "isDefault": true, "keyEquivalent": "\r" },
    ///     { "title": "Cancel", "keyEquivalent": "\u001b" }
    ///   ]
    /// }
    ///
    /// // optionsJson (all fields optional)
    /// {
    ///   "alertStyle": "informational|warning|critical",
    ///   "showsHelp": true,
    ///   "showsSuppressionButton": true,
    ///   "suppressionButtonTitle": "Do not show again",
    ///   "icon": {
    ///     "type": "systemSymbol|filePath|namedImage|appIcon|systemImage",
    ///     "value": "exclamationmark.octagon.fill",
    ///     "style": "monochrome|hierarchical|palette|multicolor",
    ///     "colors": ["white", "systemRed"],
    ///     "size": 64,
    ///     "weight": "ultraLight|thin|light|regular|medium|semibold|bold|heavy|black",
    ///     "scale": "small|medium|large"
    ///   }
    /// }
    /// ```
    /// - Parameters:
    ///   - title: Dialog title text.
    ///   - message: Optional informative message.
    ///   - buttonsJson: JSON describing the button array (see example above).
    ///   - optionsJson: JSON configuring alert style, suppression button, and optional icon.
    ///   - completion: Called on completion with `NSDictionary` containing `buttonTitle`,
    ///     `buttonIndex`, `suppressionButtonState`, `helpButtonPressed`, or an `NSError`.
    public func showDialog(
        title: String,
        message: String? = nil,
        buttonsJson: String,
        optionsJson: String,
        completion: ((NSDictionary?, NSError?) -> Void)? = nil
    ) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(String(describing: message)), buttonsJson: \(buttonsJson), optionsJson: \(optionsJson), completion: \(String(describing: completion)))")
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
            
            if let showsHelp = optionsDict["showsHelp"] as? Bool {
                options.showsHelp = showsHelp
            }
            
            if let showsSuppressionButton = optionsDict["showsSuppressionButton"] as? Bool {
                options.showsSuppressionButton = showsSuppressionButton
            }
            
            if let suppressionButtonTitle = optionsDict["suppressionButtonTitle"] as? String {
                options.suppressionButtonTitle = suppressionButtonTitle
            }
            
            if let iconDict = optionsDict["icon"] as? [String: Any] {
                if let iconConfig = IconConfiguration.from(json: iconDict) {
                    Log.d(TAG, "Parsed icon configuration: \(iconConfig)")
                    switch iconConfig.createImage() {
                    case .success(let image):
                        options.icon = image
                    case .failure(let error):
                        let nsError = NSError(domain: "DialogError", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                        completion?(nil, nsError)
                        Log.e(TAG, "Failed to create icon image skipping dialog: \(error.localizedDescription)")
                        return
                    }
                }
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
                    "suppressionButtonState": dialogResult.suppressionButtonState,
                    "helpButtonPressed": dialogResult.helpButtonPressed
                ]
                completion?(resultDict, nil)
            case .failure(let error):
                // Convert DialogError to NSError
                let nsError = NSError(domain: "DialogError", code: 0, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion?(nil, nsError)
            }
        }
    }
    
    /// Presents a single-selection open panel restricted to files.
    /// - Parameters:
    ///   - title: Panel window title displayed in the sheet.
    ///   - message: Optional informative text shown beneath the title.
    ///   - allowedContentTypes: Filename extensions (without dot) to filter; empty means no filtering.
    ///   - directoryURL: Initial directory from which browsing starts.
    ///   - completion: Invoked with the file selection dictionary or an NSError.
    public func showFileDialog(
        title: String,
        message: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil,
        completion: ((NSDictionary?, NSError?) -> Void)? = nil
    ) {
        Log.d(TAG, "showFileDialog called with title: \(title), message: \(String(describing: message)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
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
                completion?(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion?(nil, nsError)
            }
        }
    }
    
    /// Presents a multi-selection open panel restricted to files.
    /// - Parameters:
    ///   - title: Panel window title displayed in the sheet.
    ///   - message: Optional informative text shown beneath the title.
    ///   - allowedContentTypes: Filename extensions allowed for selection.
    ///   - directoryURL: Initial directory from which browsing starts.
    ///   - completion: Invoked with the selection dictionary or error.
    public func showMultiFileDialog(
        title: String,
        message: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil,
        completion: ((NSDictionary?, NSError?) -> Void)? = nil
    ) {
        Log.d(TAG, "showMultiFileDialog called with title: \(title), message: \(String(describing: message)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
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
                completion?(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion?(nil, nsError)
            }
        }
    }
    
    /// Presents a single-selection folder picker (no files allowed).
    /// - Parameters:
    ///   - title: Panel window title displayed in the sheet.
    ///   - message: Optional descriptive text shown inside the panel.
    ///   - directoryURL: Initial directory to display.
    ///   - completion: Invoked with the folder selection dictionary or error.
    public func showFolderDialog(
        title: String,
        message: String? = nil,
        directoryURL: URL? = nil,
        completion: ((NSDictionary?, NSError?) -> Void)? = nil
    ) {
        Log.d(TAG, "showFolderDialog called with title: \(title), message: \(String(describing: message)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
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
                completion?(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 2, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion?(nil, nsError)
            }
        }
    }
    
    /// Presents a multi-selection folder picker.
    /// - Parameters:
    ///   - title: Panel window title displayed in the sheet.
    ///   - message: Optional descriptive text shown inside the panel.
    ///   - directoryURL: Initial directory to display.
    ///   - completion: Invoked with the folder selection dictionary or error.
    public func showMultiFolderDialog(
        title: String,
        message: String? = nil,
        directoryURL: URL? = nil,
        completion: ((NSDictionary?, NSError?) -> Void)? = nil
    ) {
        Log.d(TAG, "showMultiFolderDialog called with title: \(title), message: \(String(describing: message)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
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
                completion?(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 2, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion?(nil, nsError)
            }
        }
    }
    
    /// Presents an `NSSavePanel` and reports the saved path back to Unity.
    /// - Parameters:
    ///   - title: Save panel window title.
    ///   - message: Optional descriptive text shown in the panel.
    ///   - nameFieldStringValue: Default filename pre-filled in the save panel.
    ///   - allowedContentTypes: Allowed extensions (empty = unrestricted).
    ///   - directoryURL: Optional starting directory.
    ///   - completion: Dictionary with `filePath`, `fileCount`, `directoryURL`, `isCancelled`,
    ///     `isSuccess`, or an error.
    public func showSaveFileDialog(
        title: String,
        message: String? = nil,
        nameFieldStringValue: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil,
        completion: ((NSDictionary?, NSError?) -> Void)? = nil
    ) {
        Log.d(TAG, "showSaveFileDialog called with title: \(title), message: \(String(describing: message)), nameFieldStringValue: \(String(describing: nameFieldStringValue)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
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
                completion?(resultDict, nil)
            case .failure(let error):
                let nsError = NSError(domain: "DialogError", code: 3, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
                completion?(nil, nsError)
            }
        }
    }
}
