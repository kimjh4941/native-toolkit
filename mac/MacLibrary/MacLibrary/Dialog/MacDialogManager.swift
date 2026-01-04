//
//  MacDialogManager.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import AppKit
import UniformTypeIdentifiers

/// Errors that can occur while configuring or presenting dialogs.
///
/// - Important: All errors are surfaced via the `Result` returned in completion handlers.
/// Use the `localizedDescription` for a developer‑friendly message. Do **not** show
/// these raw messages directly to end users unless you provide localization.
public enum DialogError: Error {
    case noButtons
    case invalidConfiguration(String)
    case executionFailed(String)
    
    /// Human readable description for debugging.
    public var localizedDescription: String {
        switch self {
        case .noButtons:
            return "No buttons specified for dialog"
        case .invalidConfiguration(let message):
            return "Invalid dialog configuration: \(message)"
        case .executionFailed(let message):
            return "Dialog execution failed: \(message)"
        }
    }
}

/// Represents a single alert action button that can optionally be the default action
/// or expose a custom key equivalent.
///
/// - Parameters:
///   - title: Visible text shown on the button.
///   - isDefault: Marks the button as the default action (Return key) when `true`.
///   - keyEquivalent: Optional single-character shortcut. Defaults to Return for default buttons.
public struct DialogButton {
    /// Visible title text.
    public let title: String
    /// Indicates that this button should act as the default (Return key binding if no custom key).
    public let isDefault: Bool
    /// Custom key equivalent (single character). If `nil` and `isDefault == true`, Return is used.
    public let keyEquivalent: String?
    
    public init(title: String, isDefault: Bool = false, keyEquivalent: String? = nil) {
        self.title = title
        self.isDefault = isDefault
        self.keyEquivalent = keyEquivalent
    }
    
    var description: String {
        return "DialogButton(title: \(title), isDefault: \(isDefault), keyEquivalent: \(String(describing: keyEquivalent)))"
    }
}

/// Container describing how an `NSAlert` should be rendered, including button ordering,
/// optional suppression checkbox, and an icon/accessory view.
///
/// - Important: The order of `buttons` determines `DialogResult.buttonIndex`.
public struct DialogOptions {
    /// The visual style of the alert (`informational`, `warning`, `critical`).
    public var alertStyle: NSAlert.Style
    /// Buttons displayed in the alert (in the provided order).
    public var buttons: [DialogButton]
    /// Whether the help button is shown.
    public var showsHelp: Bool
    /// Whether a suppression checkbox ("Do not show again") is shown.
    public var showsSuppressionButton: Bool
    /// Custom title for the suppression checkbox.
    public var suppressionButtonTitle: String?
    /// Optional icon (overrides the default app icon).
    public var icon: NSImage?
    /// Optional accessory view embedded below the message text.
    public var accessoryView: NSView?
    
    public init(
        alertStyle: NSAlert.Style = .informational,
        buttons: [DialogButton] = [DialogButton(title: "OK", isDefault: true)],
        showsHelp: Bool = false,
        showsSuppressionButton: Bool = false,
        suppressionButtonTitle: String? = nil,
        icon: NSImage? = nil,
        accessoryView: NSView? = nil
    ) {
        self.alertStyle = alertStyle
        self.buttons = buttons
        self.showsHelp = showsHelp
        self.showsSuppressionButton = showsSuppressionButton
        self.suppressionButtonTitle = suppressionButtonTitle
        self.icon = icon
        self.accessoryView = accessoryView
    }
    
    var description: String {
        return "DialogOptions(alertStyle: \(alertStyle), buttons: \(buttons), showsHelp: \(showsHelp), showsSuppressionButton: \(showsSuppressionButton), suppressionButtonTitle: \(String(describing: suppressionButtonTitle)), icon: \(String(describing: icon)), accessoryView: \(String(describing: accessoryView)))"
    }
}

/// Result returned after a dialog (alert) is dismissed.
///
/// The `buttonIndex` maps directly to `DialogOptions.buttons`. When the help button is
/// tapped, `helpButtonPressed` is flagged while the dialog remains visible until the
/// user selects a regular button.
public struct DialogResult {
    /// Index of the pressed button (0-based).
    public let buttonIndex: Int
    /// Title of the pressed button (convenience mirror of `buttons[index].title`).
    public let buttonTitle: String
    /// Whether the suppression checkbox is in the ON state.
    public let suppressionButtonState: Bool
    /// `true` if the help button was pressed.
    public let helpButtonPressed: Bool
    /// Indicates logical success (currently always `true` for a completed alert dismissal).
    public let isSuccess: Bool
    
    public init(
        buttonIndex: Int,
        buttonTitle: String,
        suppressionButtonState: Bool = false,
        helpButtonPressed: Bool = false,
        isSuccess: Bool = true
    ) {
        self.buttonIndex = buttonIndex
        self.buttonTitle = buttonTitle
        self.suppressionButtonState = suppressionButtonState
        self.helpButtonPressed = helpButtonPressed
        self.isSuccess = isSuccess
    }
    
    var description: String {
        return "DialogResult(buttonIndex: \(buttonIndex), buttonTitle: \(buttonTitle), suppressionButtonState: \(suppressionButtonState), helpButtonPressed: \(helpButtonPressed), isSuccess: \(isSuccess))"
    }
}

/// Configuration options for an open panel (file / folder picker).
///
/// Combine flags to allow files, directories, single or multiple selection.
/// `allowedContentTypes` should contain filename extensions (no leading dot).
public struct OpenDialogOptions {
    /// Allow picking regular files.
    public var canChooseFiles: Bool
    /// Allow picking directories.
    public var canChooseDirectories: Bool
    /// Allow selecting more than one item.
    public var allowsMultipleSelection: Bool
    /// Show hidden files (dotfiles) in the panel.
    public var showsHiddenFiles: Bool
    /// Allow user to create new directories from the panel.
    public var canCreateDirectories: Bool
    /// Allow selection of hidden extensions.
    public var canSelectHiddenExtension: Bool
    /// Treat package bundles (e.g. .app) as directories.
    public var treatsFilePackagesAsDirectories: Bool
    /// Allow other file types outside the allowed list.
    public var allowsOtherFileTypes: Bool
    /// Initial directory.
    public var directoryURL: URL?
    /// Pre-filled value in the name field (when relevant).
    public var nameFieldStringValue: String?
    /// The confirmation button label (e.g. "Choose").
    public var prompt: String
    /// Whether aliases are resolved automatically.
    public var resolvesAliases: Bool
    /// Whether to hide the file extension in the name field.
    public var isExtensionHidden: Bool
    /// List of filename extensions (no leading dot) used to build UTTypes for filtering.
    public var allowedContentTypes: [String]?
    
    public init(
        canChooseFiles: Bool = true,
        canChooseDirectories: Bool = false,
        allowsMultipleSelection: Bool = false,
        showsHiddenFiles: Bool = false,
        canCreateDirectories: Bool = false,
        canSelectHiddenExtension: Bool = false,
        treatsFilePackagesAsDirectories: Bool = false,
        allowsOtherFileTypes: Bool = false,
        directoryURL: URL? = nil,
        nameFieldStringValue: String? = nil,
        prompt: String = "Choose",
        resolvesAliases: Bool = true,
        isExtensionHidden: Bool = false,
        allowedContentTypes: [String]? = nil
    ) {
        self.canChooseFiles = canChooseFiles
        self.canChooseDirectories = canChooseDirectories
        self.allowsMultipleSelection = allowsMultipleSelection
        self.showsHiddenFiles = showsHiddenFiles
        self.canCreateDirectories = canCreateDirectories
        self.canSelectHiddenExtension = canSelectHiddenExtension
        self.treatsFilePackagesAsDirectories = treatsFilePackagesAsDirectories
        self.allowsOtherFileTypes = allowsOtherFileTypes
        self.directoryURL = directoryURL
        self.nameFieldStringValue = nameFieldStringValue
        self.prompt = prompt
        self.resolvesAliases = resolvesAliases
        self.isExtensionHidden = isExtensionHidden
        self.allowedContentTypes = allowedContentTypes
    }
    
    var description: String {
        return "OpenDialogOptions(canChooseFiles: \(canChooseFiles), canChooseDirectories: \(canChooseDirectories), allowsMultipleSelection: \(allowsMultipleSelection), showsHiddenFiles: \(showsHiddenFiles), canCreateDirectories: \(canCreateDirectories), canSelectHiddenExtension: \(canSelectHiddenExtension), treatsFilePackagesAsDirectories: \(treatsFilePackagesAsDirectories), allowsOtherFileTypes: \(allowsOtherFileTypes), directoryURL: \(String(describing: directoryURL)), nameFieldStringValue: \(String(describing: nameFieldStringValue)), prompt: \(prompt), resolvesAliases: \(resolvesAliases), isExtensionHidden: \(isExtensionHidden), allowedContentTypes: \(String(describing: allowedContentTypes)))"
    }
}

/// Result from an open dialog (files and/or folders).
///
/// - Note: When the user cancels the panel, `filePaths` is empty and `isCancelled == true`.
public struct OpenDialogResult {
    /// Absolute paths of selected items.
    public let filePaths: [String]
    /// Number of selected items.
    public let fileCount: Int
    /// Final directory presented by the panel (may differ from initial directory if user navigated).
    public let directoryURL: String
    /// Indicates user cancelled the panel.
    public let isCancelled: Bool
    /// Indicates logical success (panel closed normally).
    public let isSuccess: Bool
    
    public init(
        filePaths: [String],
        fileCount: Int,
        directoryURL: String,
        isCancelled: Bool = false,
        isSuccess: Bool = true
    ) {
        self.filePaths = filePaths
        self.fileCount = fileCount
        self.directoryURL = directoryURL
        self.isCancelled = isCancelled
        self.isSuccess = isSuccess
    }
    
    var description: String {
        return "OpenDialogResult(filePaths: \(filePaths), fileCount: \(fileCount), directoryURL: \(directoryURL), isCancelled: \(isCancelled), isSuccess: \(isSuccess))"
    }
}

/// Result returned from a save panel.
///
/// A save dialog always returns at most one path. `fileCount` is provided for API
/// symmetry with `OpenDialogResult`.
public struct SaveDialogResult {
    /// Absolute path chosen by the user (empty if cancelled).
    public let filePath: String
    /// File count (1 for success, 0 if cancelled).
    public let fileCount: Int
    /// Directory containing the saved item (empty if cancelled).
    public let directoryURL: String
    /// `true` if the user cancelled the panel.
    public let isCancelled: Bool
    /// Logical success (panel concluded; does not imply file creation was performed on disk).
    public let isSuccess: Bool
    
    public init(
        filePath: String,
        fileCount: Int = 1,
        directoryURL: String,
        isCancelled: Bool = false,
        isSuccess: Bool = true
    ) {
        self.filePath = filePath
        self.fileCount = fileCount
        self.directoryURL = directoryURL
        self.isCancelled = isCancelled
        self.isSuccess = isSuccess
    }
    
    var description: String {
        return "SaveDialogResult(filePath: \(filePath), fileCount: \(fileCount), directoryURL: \(directoryURL), isCancelled: \(isCancelled), isSuccess: \(isSuccess))"
    }
}

/// Central manager providing convenience APIs to present alerts, open panels and save panels.
///
/// - Thread Safety: All UI presentation is automatically marshalled onto the main thread.
/// - Usage: Call the relevant `show*` method with a completion closure to receive a typed `Result`.
public class MacDialogManager: NSObject {
    /// Internal tag for logging.
    private let TAG = "MacDialogManager"
    
    /// Shared singleton instance.
    public static let shared = MacDialogManager()
        
    private var helpButtonHandler: ((Result<DialogResult, DialogError>) -> Void)?
    
    private override init() {
        Log.d(TAG, "init")
        super.init()
    }

    /// Presents an `NSAlert` using the provided options.
    ///
    /// - Parameters:
    ///   - title: Main alert title.
    ///   - message: Informative text displayed under the title.
    ///   - options: Configuration controlling style, buttons, checkbox, and icon.
    ///   - completion: Completion handler returning a `DialogResult` or `DialogError`.
    public func showDialog(
        title: String,
        message: String? = nil,
        options: DialogOptions = DialogOptions(),
        completion: ((Result<DialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(String(describing: message)), options: \(options), completion: \(String(describing: completion))")
        
        guard !options.buttons.isEmpty else {
            Log.e(TAG, "No buttons provided")
            completion?(.failure(.noButtons))
            return
        }
        
        guard !title.isEmpty else {
            Log.e(TAG, "Empty title provided")
            completion?(.failure(.invalidConfiguration("title cannot be empty")))
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion?(.failure(.executionFailed("MacDialogManager instance deallocated")))
                return
            }
            
            do {
                helpButtonHandler = completion
                let result = try self.executeDialog(title: title, message: message, options: options)
                completion?(.success(result))
            } catch let error as DialogError {
                Log.e(self.TAG, "Dialog execution failed: \(error.localizedDescription)")
                completion?(.failure(error))
            } catch {
                Log.e(self.TAG, "Unexpected error: \(error)")
                completion?(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
    
    /// Presents an open panel (`NSOpenPanel`) with the supplied configuration.
    ///
    /// - Parameters:
    ///   - title: Window title shown in the sheet/dialog.
    ///   - message: Helper text displayed beneath the title.
    ///   - options: `OpenDialogOptions` controlling selection behavior and filtering.
    ///   - completion: Returns `OpenDialogResult` or `DialogError` via `Result`.
    public func showOpenDialog(
        title: String,
        message: String? = nil,
        options: OpenDialogOptions = OpenDialogOptions(),
        completion: ((Result<OpenDialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showOpenDialog called with title: \(title), message: \(String(describing: message)), options: \(options), completion: \(String(describing: completion))")
        
        guard !title.isEmpty else {
            Log.e(TAG, "Empty title provided")
            completion?(.failure(.invalidConfiguration("title cannot be empty")))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion?(.failure(.executionFailed("MacDialogManager instance deallocated")))
                return
            }

            do {
                let result = try self.executeOpenDialog(title: title, message: message, options: options)
                completion?(.success(result))
            } catch let error as DialogError {
                Log.e(self.TAG, "Open dialog execution failed: \(error.localizedDescription)")
                completion?(.failure(error))
            } catch {
                Log.e(self.TAG, "Unexpected error: \(error)")
                completion?(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
    
    /// Convenience wrapper for a single file selection panel.
    ///
    /// - Parameters mirror `showOpenDialog` but force single file selection.
    public func showFileDialog(
        title: String = "Select File",
        message: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil,
        completion: ((Result<OpenDialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showFileDialog called with title: \(title), message: \(String(describing: message)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
        let options = OpenDialogOptions(
            canChooseFiles: true,
            canChooseDirectories: false,
            allowsMultipleSelection: false,
            directoryURL: directoryURL,
            allowedContentTypes: allowedContentTypes
        )
        
        showOpenDialog(
            title: title,
            message: message,
            options: options,
            completion: completion
        )
    }
    
    /// Convenience wrapper for a multi file selection panel.
    ///
    /// - Parameters mirror `showOpenDialog` but allow multiple files.
    public func showMultiFileDialog(
        title: String = "Select Files",
        message: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil,
        completion: ((Result<OpenDialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showMultiFileDialog called with title: \(title), message: \(String(describing: message)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
        let options = OpenDialogOptions(
            canChooseFiles: true,
            canChooseDirectories: false,
            allowsMultipleSelection: true,
            directoryURL: directoryURL,
            allowedContentTypes: allowedContentTypes
        )
        
        showOpenDialog(
            title: title,
            message: message,
            options: options,
            completion: completion
        )
    }
    
    /// Convenience wrapper for a single folder selection panel.
    ///
    /// - Parameters mirror `showOpenDialog` but allow only one directory.
    public func showFolderDialog(
        title: String = "Select Folder",
        message: String? = nil,
        directoryURL: URL? = nil,
        completion: ((Result<OpenDialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showFolderDialog called with title: \(title), message: \(String(describing: message)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
        let options = OpenDialogOptions(
            canChooseFiles: false,
            canChooseDirectories: true,
            allowsMultipleSelection: false,
            directoryURL: directoryURL
        )
        
        showOpenDialog(
            title: title,
            message: message,
            options: options,
            completion: completion
        )
    }

    /// Convenience wrapper for a multi folder selection panel.
    ///
    /// - Parameters mirror `showOpenDialog` but allow multiple directories.
    public func showMultiFolderDialog(
        title: String = "Select Folders",
        message: String? = nil,
        directoryURL: URL? = nil,
        completion: ((Result<OpenDialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showMultiFolderDialog called with title: \(title), message: \(String(describing: message)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
        let options = OpenDialogOptions(
            canChooseFiles: false,
            canChooseDirectories: true,
            allowsMultipleSelection: true,
            directoryURL: directoryURL
        )
        
        showOpenDialog(
            title: title,
            message: message,
            options: options,
            completion: completion
        )
    }
    
    /// Presents a save panel (`NSSavePanel`).
    ///
    /// - Parameters:
    ///   - title: Window title of the save panel.
    ///   - message: Descriptive message shown inside the panel.
    ///   - nameFieldStringValue: Default file name (user may change).
    ///   - allowedContentTypes: Filename extensions used to build UTType filters.
    ///   - directoryURL: Initial directory (optional).
    ///   - completion: Returns `SaveDialogResult` or `DialogError`.
    public func showSaveFileDialog(
        title: String = "Save File",
        message: String? = nil,
        nameFieldStringValue: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil,
        completion: ((Result<SaveDialogResult, DialogError>) -> Void)? = nil
    ) {
        Log.d(TAG, "showSaveFileDialog called with title: \(title), message: \(String(describing: message)), nameFieldStringValue: \(String(describing: nameFieldStringValue)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL)), completion: \(String(describing: completion))")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion?(.failure(.executionFailed("MacDialogManager instance deallocated")))
                return
            }
            
            do {
                let result = try self.executeSaveDialog(
                    title: title,
                    message: message,
                    nameFieldStringValue: nameFieldStringValue,
                    allowedContentTypes: allowedContentTypes,
                    directoryURL: directoryURL
                )
                completion?(.success(result))
            } catch let error as DialogError {
                Log.e(self.TAG, "Save dialog execution failed: \(error.localizedDescription)")
                completion?(.failure(error))
            } catch {
                Log.e(self.TAG, "Unexpected error: \(error)")
                completion?(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
    
    private func executeSaveDialog(
        title: String,
        message: String? = nil,
        nameFieldStringValue: String? = nil,
        allowedContentTypes: [String]? = nil,
        directoryURL: URL? = nil
    ) throws -> SaveDialogResult {
        Log.d(TAG, "executeSaveDialog with title: \(title), message: \(String(describing: message)), nameFieldStringValue: \(String(describing: nameFieldStringValue)), allowedContentTypes: \(String(describing: allowedContentTypes)), directoryURL: \(String(describing: directoryURL))")
        let savePanel = NSSavePanel()
        
        savePanel.title = title
        if let message = message {
            savePanel.message = message
        }
        if let nameFieldStringValue = nameFieldStringValue {
            savePanel.nameFieldStringValue = nameFieldStringValue
        }
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        if let allowedContentTypes = allowedContentTypes, !allowedContentTypes.isEmpty {
            let utTypes = allowedContentTypes.compactMap { UTType(filenameExtension: $0) }
            if !utTypes.isEmpty {
                savePanel.allowedContentTypes = utTypes
            }
        }
        
        if let directoryURL = directoryURL {
            savePanel.directoryURL = directoryURL
        }
        
        let response = savePanel.runModal()
        
        if response == .OK {
            guard let url = savePanel.url else {
                throw DialogError.executionFailed("Save panel returned OK but no URL")
            }
            
            let result = SaveDialogResult(
                filePath: url.path,
                fileCount: 1,
                directoryURL: url.deletingLastPathComponent().path,
                isCancelled: false,
                isSuccess: true
            )
            
            Log.d(TAG, "Save dialog completed: \(url.path)")
            return result
        } else {
            let result = SaveDialogResult(
                filePath: "",
                fileCount: 0,
                directoryURL: "",
                isCancelled: true,
                isSuccess: true
            )
            
            Log.d(TAG, "Save dialog cancelled")
            return result
        }
    }
    
    private func executeDialog(
        title: String,
        message: String? = nil,
        options: DialogOptions
    ) throws -> DialogResult {
        Log.d(TAG, "executeDialog with title: \(title), message: \(String(describing: message)), options: \(options)")
        let alert = NSAlert()
        
        alert.messageText = title
        if let message = message {
            alert.informativeText = message
        }
        alert.alertStyle = options.alertStyle
        alert.showsHelp = options.showsHelp
        alert.showsSuppressionButton = options.showsSuppressionButton
        
        if options.showsHelp {
            alert.delegate = self
        } else {
            alert.delegate = nil
        }
        
        if let suppressionTitle = options.suppressionButtonTitle {
            alert.suppressionButton?.title = suppressionTitle
        }
        
        if let icon = options.icon {
            alert.icon = icon
        }
        
        if let accessoryView = options.accessoryView {
            alert.accessoryView = accessoryView
        }
        
        for button in options.buttons {
            Log.d(TAG, "Adding button: \(button.title), isDefault: \(button.isDefault), keyEquivalent: \(button.keyEquivalent ?? "nil")")
            let alertButton = alert.addButton(withTitle: button.title)
            
            if button.isDefault {
                alertButton.keyEquivalent = "\r"
            } else if let keyEquivalent = button.keyEquivalent {
                alertButton.keyEquivalent = keyEquivalent
            }
            Log.d(TAG, "Button added with keyEquivalent: \(alertButton.keyEquivalent)")
        }
        
        let response = alert.runModal()
        let buttonIndex = getButtonIndex(from: response)
        
        guard buttonIndex >= 0 && buttonIndex < options.buttons.count else {
            throw DialogError.executionFailed("Invalid button response: \(response.rawValue)")
        }
        
        let buttonTitle = options.buttons[buttonIndex].title
        let suppressionButtonState = alert.suppressionButton?.state == .on
        
        let result = DialogResult(
            buttonIndex: buttonIndex,
            buttonTitle: buttonTitle,
            suppressionButtonState: suppressionButtonState,
            helpButtonPressed: false,
            isSuccess: true
        )
        Log.d(TAG, "Dialog completed: \(result)")
        return result
    }
    
    private func getButtonIndex(from response: NSApplication.ModalResponse) -> Int {
        switch response {
        case .alertFirstButtonReturn:
            return 0
        case .alertSecondButtonReturn:
            return 1
        case .alertThirdButtonReturn:
            return 2
        default:
            let baseValue = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let index = Int(response.rawValue) - Int(baseValue)
            return max(0, index)
        }
    }
    
    private func executeOpenDialog(
        title: String,
        message: String? = nil,
        options: OpenDialogOptions
    ) throws -> OpenDialogResult {
        Log.d(TAG, "executeOpenDialog with title: \(title), message: \(String(describing: message)), options: \(options)")
        let openPanel = NSOpenPanel()

        openPanel.title = title
        if let message = message {
            openPanel.message = message
        }
        openPanel.canChooseFiles = options.canChooseFiles
        openPanel.canChooseDirectories = options.canChooseDirectories
        openPanel.allowsMultipleSelection = options.allowsMultipleSelection
        openPanel.showsHiddenFiles = options.showsHiddenFiles
        openPanel.canCreateDirectories = options.canCreateDirectories
        openPanel.canSelectHiddenExtension = options.canSelectHiddenExtension
        openPanel.treatsFilePackagesAsDirectories = options.treatsFilePackagesAsDirectories
        openPanel.allowsOtherFileTypes = options.allowsOtherFileTypes
        if let nameFieldStringValue = options.nameFieldStringValue {
            openPanel.nameFieldStringValue = nameFieldStringValue
        }
        openPanel.prompt = options.prompt
        openPanel.resolvesAliases = options.resolvesAliases
        openPanel.isExtensionHidden = options.isExtensionHidden
        
        if let allowedContentTypes = options.allowedContentTypes, !allowedContentTypes.isEmpty {
            let utTypes = allowedContentTypes.compactMap { UTType(filenameExtension: $0) }
            if !utTypes.isEmpty {
                openPanel.allowedContentTypes = utTypes
            }
        }
        
        if let directoryURL = options.directoryURL {
            openPanel.directoryURL = directoryURL
        }

        let response = openPanel.runModal()

        if response == .OK {
            let urls = openPanel.urls
            let filePaths = urls.map { $0.path }

            let result = OpenDialogResult(
                filePaths: filePaths,
                fileCount: filePaths.count,
                directoryURL: openPanel.directoryURL?.path ?? "",
                isCancelled: false,
                isSuccess: true
            )

            Log.d(TAG, "Open dialog completed: \(filePaths.count) files selected")
            return result
        } else {
            let result = OpenDialogResult(
                filePaths: [],
                fileCount: 0,
                directoryURL: "",
                isCancelled: true,
                isSuccess: true
            )

            Log.d(TAG, "Open dialog cancelled")
            return result
        }
    }
}

extension MacDialogManager: NSAlertDelegate {
    public func alertShowHelp(_ alert: NSAlert) -> Bool {
        Log.d(TAG, "Help button pressed")
        helpButtonHandler?(
            .success(
                DialogResult(
                    buttonIndex: -1,
                    buttonTitle: "",
                    suppressionButtonState: alert.suppressionButton?.state == .on,
                    helpButtonPressed: true,
                    isSuccess: true
                )
            )
        )
        return true
    }
}
