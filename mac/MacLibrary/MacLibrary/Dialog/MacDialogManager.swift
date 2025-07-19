//
//  MacDialogManager.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/04/20.
//
import AppKit
import UniformTypeIdentifiers

public enum DialogError: Error {
    case noButtons
    case invalidConfiguration
    case executionFailed(String)
    
    public var localizedDescription: String {
        switch self {
        case .noButtons:
            return "No buttons specified for dialog"
        case .invalidConfiguration:
            return "Invalid dialog configuration"
        case .executionFailed(let message):
            return "Dialog execution failed: \(message)"
        }
    }
}

public struct DialogButton {
    public let title: String
    public let isDefault: Bool
    public let keyEquivalent: String?
    
    public init(title: String, isDefault: Bool = false, keyEquivalent: String? = nil) {
        self.title = title
        self.isDefault = isDefault
        self.keyEquivalent = keyEquivalent
    }
}

public struct DialogOptions {
    public var alertStyle: NSAlert.Style
    public var buttons: [DialogButton]
    public var showsHelp: Bool
    public var showsSuppressionButton: Bool
    public var suppressionButtonTitle: String?
    public var icon: NSImage?
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
}

public struct DialogResult {
    public let buttonIndex: Int
    public let buttonTitle: String
    public let suppressionButtonState: Bool
    public let isSuccess: Bool
    
    public init(
        buttonIndex: Int,
        buttonTitle: String,
        suppressionButtonState: Bool = false,
        isSuccess: Bool = true
    ) {
        self.buttonIndex = buttonIndex
        self.buttonTitle = buttonTitle
        self.suppressionButtonState = suppressionButtonState
        self.isSuccess = isSuccess
    }
}

public struct OpenDialogOptions {
    public var canChooseFiles: Bool
    public var canChooseDirectories: Bool
    public var allowsMultipleSelection: Bool
    public var showsHiddenFiles: Bool
    public var canCreateDirectories: Bool
    public var canSelectHiddenExtension: Bool
    public var treatsFilePackagesAsDirectories: Bool
    public var allowsOtherFileTypes: Bool
    public var directoryURL: URL?
    public var nameFieldStringValue: String
    public var prompt: String
    public var resolvesAliases: Bool
    public var isExtensionHidden: Bool
    public var allowedContentTypes: [String]

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
        nameFieldStringValue: String = "",
        prompt: String = "Choose",
        resolvesAliases: Bool = true,
        isExtensionHidden: Bool = false,
        allowedContentTypes: [String] = []
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
}

public struct OpenDialogResult {
    public let filePaths: [String]
    public let fileCount: Int
    public let directoryURL: String
    public let isCancelled: Bool
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
}

public struct SaveDialogResult {
    public let filePath: String
    public let fileCount: Int
    public let directoryURL: String
    public let isCancelled: Bool
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
}

public class MacDialogManager: NSObject {

    private let TAG = "MacDialogManager"

    public static let shared = MacDialogManager()

    private override init() {
        Log.d(TAG, "init")
        super.init()
    }

    public func showDialog(
        title: String,
        message: String,
        options: DialogOptions = DialogOptions(),
        completion: @escaping (Result<DialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showDialog called with title: \(title), message: \(message)")

        guard !options.buttons.isEmpty else {
            Log.e(TAG, "No buttons provided")
            completion(.failure(.noButtons))
            return
        }
        
        guard !title.isEmpty else {
            Log.e(TAG, "Empty title provided")
            completion(.failure(.invalidConfiguration))
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(.failure(.executionFailed("MacDialogManager instance deallocated")))
                return
            }
            
            do {
                let result = try self.executeDialog(title: title, message: message, options: options)
                completion(.success(result))
            } catch let error as DialogError {
                Log.e(self.TAG, "Dialog execution failed: \(error.localizedDescription)")
                completion(.failure(error))
            } catch {
                Log.e(self.TAG, "Unexpected error: \(error)")
                completion(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
    
    public func showOpenDialog(
        title: String,
        message: String,
        options: OpenDialogOptions = OpenDialogOptions(),
        completion: @escaping (Result<OpenDialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showOpenDialog called with title: \(title), message: \(message)")

        guard !title.isEmpty else {
            Log.e(TAG, "Empty title provided")
            completion(.failure(.invalidConfiguration))
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(.failure(.executionFailed("MacDialogManager instance deallocated")))
                return
            }

            do {
                let result = try self.executeOpenDialog(title: title, message: message, options: options)
                completion(.success(result))
            } catch let error as DialogError {
                Log.e(self.TAG, "Open dialog execution failed: \(error.localizedDescription)")
                completion(.failure(error))
            } catch {
                Log.e(self.TAG, "Unexpected error: \(error)")
                completion(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
    
    public func showFileDialog(
        title: String = "ファイルを選択",
        message: String = "ファイルを選択してください",
        allowedContentTypes: [String] = [],
        directoryURL: URL? = nil,
        completion: @escaping (Result<OpenDialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showFileDialog called with title: \(title)")

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
    
    public func showMultiFileDialog(
        title: String = "ファイルを選択",
        message: String = "ファイルを選択してください（複数選択可能）",
        allowedContentTypes: [String] = [],
        directoryURL: URL? = nil,
        completion: @escaping (Result<OpenDialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showMultiFileDialog called with title: \(title)")
        
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
    
    public func showFolderDialog(
        title: String = "フォルダを選択",
        message: String = "フォルダを選択してください",
        directoryURL: URL? = nil,
        completion: @escaping (Result<OpenDialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showFolderDialog called with title: \(title)")

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

    public func showMultiFolderDialog(
        title: String = "フォルダを選択",
        message: String = "フォルダを選択してください（複数選択可能）",
        directoryURL: URL? = nil,
        completion: @escaping (Result<OpenDialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showMultiFolderDialog called with title: \(title)")
        
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
    
    public func showSaveFileDialog(
        title: String = "ファイルを保存",
        message: String = "ファイルを保存してください",
        nameFieldStringValue: String = "",
        allowedContentTypes: [String] = [],
        directoryURL: URL? = nil,
        completion: @escaping (Result<SaveDialogResult, DialogError>) -> Void
    ) {
        Log.d(TAG, "showSaveFileDialog called with title: \(title)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(.failure(.executionFailed("MacDialogManager instance deallocated")))
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
                completion(.success(result))
            } catch let error as DialogError {
                Log.e(self.TAG, "Save dialog execution failed: \(error.localizedDescription)")
                completion(.failure(error))
            } catch {
                Log.e(self.TAG, "Unexpected error: \(error)")
                completion(.failure(.executionFailed(error.localizedDescription)))
            }
        }
    }
    
    private func executeSaveDialog(
        title: String,
        message: String,
        nameFieldStringValue: String,
        allowedContentTypes: [String],
        directoryURL: URL?
    ) throws -> SaveDialogResult {
        let savePanel = NSSavePanel()
        
        savePanel.title = title
        savePanel.message = message
        savePanel.nameFieldStringValue = nameFieldStringValue
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        
        if !allowedContentTypes.isEmpty {
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
                isSuccess: false
            )
            
            Log.d(TAG, "Save dialog cancelled")
            return result
        }
    }
    
    private func executeDialog(
        title: String,
        message: String,
        options: DialogOptions
    ) throws -> DialogResult {
        let alert = NSAlert()
        
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = options.alertStyle
        alert.showsHelp = options.showsHelp
        alert.showsSuppressionButton = options.showsSuppressionButton
        
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
            let alertButton = alert.addButton(withTitle: button.title)
            
            if button.isDefault {
                alertButton.keyEquivalent = button.keyEquivalent ?? "\r"
            } else if let keyEquivalent = button.keyEquivalent {
                alertButton.keyEquivalent = keyEquivalent
            }
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
            isSuccess: true
        )
        
        Log.d(TAG, "Button pressed: \(buttonTitle) (index: \(buttonIndex))")
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
        message: String,
        options: OpenDialogOptions
    ) throws -> OpenDialogResult {
        let openPanel = NSOpenPanel()

        openPanel.title = title
        openPanel.message = message
        openPanel.canChooseFiles = options.canChooseFiles
        openPanel.canChooseDirectories = options.canChooseDirectories
        openPanel.allowsMultipleSelection = options.allowsMultipleSelection
        openPanel.showsHiddenFiles = options.showsHiddenFiles
        openPanel.canCreateDirectories = options.canCreateDirectories
        openPanel.canSelectHiddenExtension = options.canSelectHiddenExtension
        openPanel.treatsFilePackagesAsDirectories = options.treatsFilePackagesAsDirectories
        openPanel.allowsOtherFileTypes = options.allowsOtherFileTypes
        openPanel.nameFieldStringValue = options.nameFieldStringValue
        openPanel.prompt = options.prompt
        openPanel.resolvesAliases = options.resolvesAliases
        openPanel.isExtensionHidden = options.isExtensionHidden
        
        if !options.allowedContentTypes.isEmpty {
            let utTypes = options.allowedContentTypes.compactMap { UTType(filenameExtension: $0) }
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
                isSuccess: false
            )

            Log.d(TAG, "Open dialog cancelled")
            return result
        }
    }
}
