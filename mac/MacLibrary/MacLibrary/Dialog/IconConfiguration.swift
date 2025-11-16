//
//  IconConfiguration.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2025/10/13.
//
import AppKit

public struct IconConfiguration {
    
    private let TAG = "IconConfiguration"
    
    /// アイコンのタイプ
    public enum IconType: String {
        case systemSymbol = "systemsymbol"
        case filePath = "filepath"
        case namedImage = "namedimage"
        case appIcon = "appicon"
        case systemImage = "systemimage"
    }
    
    /// レンダリングスタイル
    public enum RenderingMode: String {
        case monochrome      // 単色
        case hierarchical    // 階層
        case palette         // パレット
        case multicolor      // マルチカラー
    }
    
    public var type: IconType
    public var value: String?
    public var renderingMode: RenderingMode?
    public var colors: [String]
    public var size: CGFloat?
    public var weight: String?
    public var scale: String?
    
    public init(
        type: IconType = .systemSymbol,
        value: String? = nil,
        renderingMode: RenderingMode? = nil,
        colors: [String] = [],
        size: CGFloat? = nil,
        weight: String? = nil,
        scale: String? = nil
    ) {
        self.type = type
        self.value = value
        self.renderingMode = renderingMode
        self.colors = colors
        self.size = size
        self.weight = weight
        self.scale = scale
    }
    
    public var description: String {
        return "IconConfiguration(type: \(type), value: \(String(describing: value)), renderingMode: \(String(describing: renderingMode)), colors: \(colors), size: \(String(describing: size)), weight: \(String(describing: weight)), scale: \(String(describing: scale)))"
    }
}

extension IconConfiguration {
    
    public static func from(json: [String: Any]) -> IconConfiguration? {
        Log.d("IconConfiguration", "from json: \(json)")
        // type の取得
        guard let typeString = json["type"] as? String,
              let type = IconType(rawValue: typeString.lowercased()) else {
            return nil
        }
        
        let value = json["value"] as? String
        
        // rendering mode
        let renderingMode: RenderingMode?
        if let modeString = json["mode"] as? String {
            renderingMode = RenderingMode(rawValue: modeString.lowercased())
        } else {
            renderingMode = nil
        }
        
        // colors
        let colors = json["colors"] as? [String] ?? []

        // size
        let size: CGFloat?
        if let sizeValue = json["size"] as? NSNumber {
            size = CGFloat(sizeValue.doubleValue)
        } else {
            size = nil
        }

        // weight
        let weight = json["weight"] as? String

        // scale
        let scale = json["scale"] as? String

        return IconConfiguration(
            type: type,
            value: value,
            renderingMode: renderingMode,
            colors: colors,
            size: size,
            weight: weight,
            scale: scale
        )
    }
    
    /// IconConfiguration から NSImage を生成
    public func createImage() -> Result<NSImage, DialogError> {
        Log.d(TAG, "createImage")
        switch type {
        case .systemSymbol:
            guard let value = value else {
                Log.e(TAG, "Value is required for systemSymbol type")
                return .failure(.invalidConfiguration("Value is required for systemSymbol type"))
            }
            guard let image = NSImage(systemSymbolName: value, accessibilityDescription: nil) else {
                Log.e(TAG, "Failed to create system symbol image: \(value)")
                return .failure(.invalidConfiguration("Failed to create system symbol image: \(value)"))
            }
            Log.d(TAG, "Successfully created system symbol image: \(value)")
            return .success(applyConfiguration(to: image))
        case .filePath:
            guard let value = value else {
                Log.e(TAG, "Value is required for filePath type")
                return .failure(.invalidConfiguration("Value is required for filePath type"))
            }
            let expandedPath = NSString(string: value).expandingTildeInPath
            guard let image = NSImage(contentsOfFile: expandedPath) else {
                Log.e(TAG, "Failed to create image from file path: \(expandedPath)")
                return .failure(.invalidConfiguration("Failed to create image from file path: \(expandedPath)"))
            }
            Log.d(TAG, "Successfully created image from file path: \(expandedPath)")
            return .success(image)
        case .namedImage:
            guard let value = value else {
                Log.e(TAG, "Value is required for namedImage type")
                return .failure(.invalidConfiguration("Value is required for namedImage type"))
            }
            guard let image = NSImage(named: value) else {
                Log.e(TAG, "Failed to create named image: \(value)")
                return .failure(.invalidConfiguration("Failed to create named image: \(value)"))
            }
            Log.d(TAG, "Successfully created named image: \(value)")
            return .success(image)
        case .appIcon:
            guard let image = NSImage(named: NSImage.applicationIconName) else {
                Log.e(TAG, "Failed to create application icon image")
                return .failure(.invalidConfiguration("Failed to create application icon image"))
            }
            Log.d(TAG, "Successfully created application icon image")
            return .success(image)
        case .systemImage:
            guard let value = value else {
                Log.e(TAG, "Value is required for systemImage type")
                return .failure(.invalidConfiguration("Value is required for systemImage type"))
            }
            guard let systemImageName = systemImageName(for: value) else {
                Log.e(TAG, "Invalid system image name: \(value)")
                return .failure(.invalidConfiguration("Invalid system image name: \(value)"))
            }
            guard let image = NSImage(named: systemImageName) else {
                Log.e(TAG, "Failed to create system image: \(value)")
                return .failure(.invalidConfiguration("Failed to create system image: \(value)"))
            }
            Log.d(TAG, "Successfully created system image: \(value)")
            return .success(image)
        }
    }
    
    private func applyConfiguration(to image: NSImage) -> NSImage {
        Log.d(TAG, "applyConfiguration")
        var config = NSImage.SymbolConfiguration()
        
        // size と weight を適用
        if let size = size, let weightValue = parseWeight() {
            config = config.applying(.init(pointSize: size, weight: weightValue))
            Log.d("IconConfiguration", "Applying size: \(size), weight: \(weightValue)")
        } else if let size = size {
            config = config.applying(.init(pointSize: size, weight: .regular))
            Log.d("IconConfiguration", "Applying size: \(size), weight: regular(default)")
        } else if let weightValue = parseWeight() {
            config = config.applying(.init(pointSize: 16, weight: weightValue))
            Log.d("IconConfiguration", "Applying size: 16(default), weight: \(weightValue)")
        }
        
        // scale を適用
        if let scaleValue = parseScale() {
            config = config.applying(.init(scale: scaleValue))
            Log.d("IconConfiguration", "Applying scale: \(scaleValue)")
        }
        
        let parsedColors = parseColors()
        // rendering mode と colors を適用
        if let renderingMode = renderingMode {
            switch renderingMode {
            case .monochrome:
                config = config.applying(.preferringMonochrome())
                Log.d("IconConfiguration", "Applying monochrome rendering mode")
            case .hierarchical:
                if !colors.isEmpty, let firstColor = parsedColors.first {
                    config = config.applying(.init(hierarchicalColor: firstColor))
                    Log.d("IconConfiguration", "Applying hierarchical rendering mode with color: \(firstColor)")
                } else {
                    config = config.applying(.preferringHierarchical())
                    Log.d("IconConfiguration", "Applying hierarchical rendering mode with default color")
                }
            case .palette:
                if !colors.isEmpty {
                    config = config.applying(.init(paletteColors: parsedColors))
                    Log.d("IconConfiguration", "Applying palette rendering mode with colors: \(parsedColors)")
                }
            case .multicolor:
                config = config.applying(.preferringMulticolor())
                Log.d("IconConfiguration", "Applying multicolor rendering mode")
            }
        }
        image.isTemplate = false
        return image.withSymbolConfiguration(config) ?? image
    }
    
    private func parseColors() -> [NSColor] {
        return colors.compactMap { colorString in
            switch colorString.lowercased() {
            case "systemred":
                Log.d("IconConfiguration", "Parsed color: systemRed")
                return .systemRed
            case "systemblue":
                Log.d("IconConfiguration", "Parsed color: systemBlue")
                return .systemBlue
            case "systemgreen":
                Log.d("IconConfiguration", "Parsed color: systemGreen")
                return .systemGreen
            case "systemyellow":
                Log.d("IconConfiguration", "Parsed color: systemYellow")
                return .systemYellow
            case "systemorange":
                Log.d("IconConfiguration", "Parsed color: systemOrange")
                return .systemOrange
            case "systempink":
                Log.d("IconConfiguration", "Parsed color: systemPink")
                return .systemPink
            case "systempurple":
                Log.d("IconConfiguration", "Parsed color: systemPurple")
                return .systemPurple
            case "systemteal":
                Log.d("IconConfiguration", "Parsed color: systemTeal")
                return .systemTeal
            case "systemindigo":
                Log.d("IconConfiguration", "Parsed color: systemIndigo")
                return .systemIndigo
            case "systembrown":
                Log.d("IconConfiguration", "Parsed color: systemBrown")
                return .systemBrown
            case "systemgray":
                Log.d("IconConfiguration", "Parsed color: systemGray")
                return .systemGray
            case "white":
                Log.d("IconConfiguration", "Parsed color: white")
                return .white
            case "black":
                Log.d("IconConfiguration", "Parsed color: black")
                return .black
            case "labelcolor":
                Log.d("IconConfiguration", "Parsed color: labelColor")
                return .labelColor
            case "secondarylabelcolor":
                Log.d("IconConfiguration", "Parsed color: secondaryLabelColor")
                return .secondaryLabelColor
            default:
                // HEX color support (#RRGGBB)
                if colorString.hasPrefix("#") {
                    Log.d("IconConfiguration", "Parsed HEX color: \(colorString)")
                    return NSColor(hexString: colorString)
                }
                Log.d("IconConfiguration", "Unknown color: \(colorString)")
                return nil
            }
        }
    }
    
    private func parseWeight() -> NSFont.Weight? {
        guard let weight = weight else { return nil }
        
        switch weight.lowercased() {
        case "ultralight":
            Log.d("IconConfiguration", "Parsed weight: ultralight")
            return .ultraLight
        case "thin":
            Log.d("IconConfiguration", "Parsed weight: thin")
            return .thin
        case "light":
            Log.d("IconConfiguration", "Parsed weight: light")
            return .light
        case "regular":
            Log.d("IconConfiguration", "Parsed weight: regular")
            return .regular
        case "medium":
            Log.d("IconConfiguration", "Parsed weight: medium")
            return .medium
        case "semibold":
            Log.d("IconConfiguration", "Parsed weight: semibold")
            return .semibold
        case "bold":
            Log.d("IconConfiguration", "Parsed weight: bold")
            return .bold
        case "heavy":
            Log.d("IconConfiguration", "Parsed weight: heavy")
            return .heavy
        case "black":
            Log.d("IconConfiguration", "Parsed weight: black")
            return .black
        default:
            Log.d("IconConfiguration", "Unknown weight: \(weight)")
            return nil
        }
    }
    
    private func parseScale() -> NSImage.SymbolScale? {
        guard let scale = scale else { return nil }
        
        switch scale.lowercased() {
        case "small":
            Log.d("IconConfiguration", "Parsed scale: small")
            return .small
        case "medium":
            Log.d("IconConfiguration", "Parsed scale: medium")
            return .medium
        case "large":
            Log.d("IconConfiguration", "Parsed scale: large")
            return .large
        default:
            Log.d("IconConfiguration", "Unknown scale: \(scale)")
            return nil
        }
    }
    
    private func systemImageName(for value: String) -> String? {
        switch value.lowercased() {
        // Basic System Images (macOS 10.5+)
        case "addtemplatename": return NSImage.addTemplateName
        case "bluetoothtemplatename": return NSImage.bluetoothTemplateName
        case "bonjourname": return NSImage.bonjourName
        case "bookmarkstemplatename": return NSImage.bookmarksTemplateName
        case "cautionname": return NSImage.cautionName
        case "computername": return NSImage.computerName
        case "enterfullscreentemplatename": return NSImage.enterFullScreenTemplateName
        case "exitfullscreentemplatename": return NSImage.exitFullScreenTemplateName
        case "foldername": return NSImage.folderName
        case "folderburnablename": return NSImage.folderBurnableName
        case "foldersmartname": return NSImage.folderSmartName
        case "followlinkfreestandingtemplatename": return NSImage.followLinkFreestandingTemplateName
        case "hometemplatename": return NSImage.homeTemplateName
        case "ichattheatertemplatename": return NSImage.iChatTheaterTemplateName
        case "locklockedtemplatename": return NSImage.lockLockedTemplateName
        case "lockunlockedtemplatename": return NSImage.lockUnlockedTemplateName
        case "networkname": return NSImage.networkName
        case "pathtemplatename": return NSImage.pathTemplateName
        case "quicklooktemplatename": return NSImage.quickLookTemplateName
        case "refreshfreestandingtemplatename": return NSImage.refreshFreestandingTemplateName
        case "refreshtemplatename": return NSImage.refreshTemplateName
        case "removetemplatename": return NSImage.removeTemplateName
        case "revealfreestandingtemplatename": return NSImage.revealFreestandingTemplateName
        case "sharetemplatename": return NSImage.shareTemplateName
        case "slideshowtemplatename": return NSImage.slideshowTemplateName
        case "statusavailablename": return NSImage.statusAvailableName
        case "statusnonename": return NSImage.statusNoneName
        case "statuspartiallyavailablename": return NSImage.statusPartiallyAvailableName
        case "statusunavailablename": return NSImage.statusUnavailableName
        case "stopprogressfreestandingtemplatename": return NSImage.stopProgressFreestandingTemplateName
        case "stopprogresstemplatename": return NSImage.stopProgressTemplateName
        case "trashemptyname": return NSImage.trashEmptyName
        case "trashfullname": return NSImage.trashFullName
        case "actiontemplatename": return NSImage.actionTemplateName
        case "smartbadgetemplatename": return NSImage.smartBadgeTemplateName
        case "iconviewtemplatename": return NSImage.iconViewTemplateName
        case "listviewtemplatename": return NSImage.listViewTemplateName
        case "columnviewtemplatename": return NSImage.columnViewTemplateName
        case "flowviewtemplatename": return NSImage.flowViewTemplateName
        case "invaliddatafreestandingtemplatename": return NSImage.invalidDataFreestandingTemplateName
        case "goforwardtemplatename": return NSImage.goForwardTemplateName
        case "gobacktemplatename": return NSImage.goBackTemplateName
        case "gorighttemplatename": return NSImage.goRightTemplateName
        case "golefttemplatename": return NSImage.goLeftTemplateName
        case "rightfacingtriangletemplatename": return NSImage.rightFacingTriangleTemplateName
        case "leftfacingtriangletemplatename": return NSImage.leftFacingTriangleTemplateName
        case "mobilemename": return NSImage.mobileMeName
        case "multipledocumentsname": return NSImage.multipleDocumentsName
        case "useraccountsname": return NSImage.userAccountsName
        case "preferencesgeneralname": return NSImage.preferencesGeneralName
        case "advancedname": return NSImage.advancedName
        case "infoname": return NSImage.infoName
        case "fontpanelname": return NSImage.fontPanelName
        case "colorpanelname": return NSImage.colorPanelName
        case "username": return NSImage.userName
        case "usergroupname": return NSImage.userGroupName
        case "everyonename": return NSImage.everyoneName
        case "userguestname": return NSImage.userGuestName
        case "menuonstatetemplatename": return NSImage.menuOnStateTemplateName
        case "menumixedstatetemplatename": return NSImage.menuMixedStateTemplateName
        case "applicationiconname": return NSImage.applicationIconName

        // Touch Bar Images (macOS 10.12.2+)
        case "touchbaradddetailtemplatename": return NSImage.touchBarAddDetailTemplateName
        case "touchbaraddtemplatename": return NSImage.touchBarAddTemplateName
        case "touchbaralarmtemplatename": return NSImage.touchBarAlarmTemplateName
        case "touchbaraudioinputmutetemplatename": return NSImage.touchBarAudioInputMuteTemplateName
        case "touchbaraudioinputtemplatename": return NSImage.touchBarAudioInputTemplateName
        case "touchbaraudiooutputmutetemplatename": return NSImage.touchBarAudioOutputMuteTemplateName
        case "touchbaraudiooutputvolumehightemplatename": return NSImage.touchBarAudioOutputVolumeHighTemplateName
        case "touchbaraudiooutputvolumelowtemplatename": return NSImage.touchBarAudioOutputVolumeLowTemplateName
        case "touchbaraudiooutputvolumemediumtemplatename": return NSImage.touchBarAudioOutputVolumeMediumTemplateName
        case "touchbaraudiooutputvolumeofftemplatename": return NSImage.touchBarAudioOutputVolumeOffTemplateName
        case "touchbarbookmarkstemplatename": return NSImage.touchBarBookmarksTemplateName
        case "touchbarcolorpickerfillname": return NSImage.touchBarColorPickerFillName
        case "touchbarcolorpickerfontname": return NSImage.touchBarColorPickerFontName
        case "touchbarcolorpickerstrokename": return NSImage.touchBarColorPickerStrokeName
        case "touchbarcommunicationaudiotemplatename": return NSImage.touchBarCommunicationAudioTemplateName
        case "touchbarcommunicationvideotemplatename": return NSImage.touchBarCommunicationVideoTemplateName
        case "touchbarcomposetemplatename": return NSImage.touchBarComposeTemplateName
        case "touchbardeletetemplatename": return NSImage.touchBarDeleteTemplateName
        case "touchbardownloadtemplatename": return NSImage.touchBarDownloadTemplateName
        case "touchbarenterfullscreentemplatename": return NSImage.touchBarEnterFullScreenTemplateName
        case "touchbarexitfullscreentemplatename": return NSImage.touchBarExitFullScreenTemplateName
        case "touchbarfastforwardtemplatename": return NSImage.touchBarFastForwardTemplateName
        case "touchbarfoldercopytotemplatename": return NSImage.touchBarFolderCopyToTemplateName
        case "touchbarfoldermovetotemplatename": return NSImage.touchBarFolderMoveToTemplateName
        case "touchbarfoldertemplatename": return NSImage.touchBarFolderTemplateName
        case "touchbargetinfotemplatename": return NSImage.touchBarGetInfoTemplateName
        case "touchbargobacktemplatename": return NSImage.touchBarGoBackTemplateName
        case "touchbargodowntemplatename": return NSImage.touchBarGoDownTemplateName
        case "touchbargoforwardtemplatename": return NSImage.touchBarGoForwardTemplateName
        case "touchbargouptemplatename": return NSImage.touchBarGoUpTemplateName
        case "touchbarhistorytemplatename": return NSImage.touchBarHistoryTemplateName
        case "touchbariconviewtemplatename": return NSImage.touchBarIconViewTemplateName
        case "touchbarlistviewtemplatename": return NSImage.touchBarListViewTemplateName
        case "touchbarmailtemplatename": return NSImage.touchBarMailTemplateName
        case "touchbarnewfoldertemplatename": return NSImage.touchBarNewFolderTemplateName
        case "touchbarnewmessagetemplatename": return NSImage.touchBarNewMessageTemplateName
        case "touchbaropeninbrowsertemplatename": return NSImage.touchBarOpenInBrowserTemplateName
        case "touchbarpausetemplatename": return NSImage.touchBarPauseTemplateName
        case "touchbarplaypausetemplatename": return NSImage.touchBarPlayPauseTemplateName
        case "touchbarplaytemplatename": return NSImage.touchBarPlayTemplateName
        case "touchbarquicklooktemplatename": return NSImage.touchBarQuickLookTemplateName
        case "touchbarrecordstarttemplatename": return NSImage.touchBarRecordStartTemplateName
        case "touchbarrecordstoptemplatename": return NSImage.touchBarRecordStopTemplateName
        case "touchbarrefreshtemplatename": return NSImage.touchBarRefreshTemplateName
        case "touchbarremovetemplatename": return NSImage.touchBarRemoveTemplateName
        case "touchbarrewindtemplatename": return NSImage.touchBarRewindTemplateName
        case "touchbarrotatelefttemplatename": return NSImage.touchBarRotateLeftTemplateName
        case "touchbarrotaterighttemplatename": return NSImage.touchBarRotateRightTemplateName
        case "touchbarsearchtemplatename": return NSImage.touchBarSearchTemplateName
        case "touchbarsharetemplatename": return NSImage.touchBarShareTemplateName
        case "touchbarsidebartemplatename": return NSImage.touchBarSidebarTemplateName
        case "touchbarskipahead15secondstemplatename": return NSImage.touchBarSkipAhead15SecondsTemplateName
        case "touchbarskipahead30secondstemplatename": return NSImage.touchBarSkipAhead30SecondsTemplateName
        case "touchbarskipaheadtemplatename": return NSImage.touchBarSkipAheadTemplateName
        case "touchbarskipback15secondstemplatename": return NSImage.touchBarSkipBack15SecondsTemplateName
        case "touchbarskipback30secondstemplatename": return NSImage.touchBarSkipBack30SecondsTemplateName
        case "touchbarskipbacktemplatename": return NSImage.touchBarSkipBackTemplateName
        case "touchbarskiptoendtemplatename": return NSImage.touchBarSkipToEndTemplateName
        case "touchbarskiptostarttemplatename": return NSImage.touchBarSkipToStartTemplateName
        case "touchbarslideshowtemplatename": return NSImage.touchBarSlideshowTemplateName
        case "touchbartagicontemplatename": return NSImage.touchBarTagIconTemplateName
        case "touchbartextboldtemplatename": return NSImage.touchBarTextBoldTemplateName
        case "touchbartextboxtemplatename": return NSImage.touchBarTextBoxTemplateName
        case "touchbartextcenteraligntemplatename": return NSImage.touchBarTextCenterAlignTemplateName
        case "touchbartextitalictemplatename": return NSImage.touchBarTextItalicTemplateName
        case "touchbartextjustifiedaligntemplatename": return NSImage.touchBarTextJustifiedAlignTemplateName
        case "touchbartextleftaligntemplatename": return NSImage.touchBarTextLeftAlignTemplateName
        case "touchbartextlisttemplatename": return NSImage.touchBarTextListTemplateName
        case "touchbartextrightaligntemplatename": return NSImage.touchBarTextRightAlignTemplateName
        case "touchbartextstrikethroughtemplatename": return NSImage.touchBarTextStrikethroughTemplateName
        case "touchbartextunderlinetemplatename": return NSImage.touchBarTextUnderlineTemplateName
        case "touchbaruseraddtemplatename": return NSImage.touchBarUserAddTemplateName
        case "touchbarusergrouptemplatename": return NSImage.touchBarUserGroupTemplateName
        case "touchbarusertemplatename": return NSImage.touchBarUserTemplateName
        case "touchbarvolumedowntemplatename": return NSImage.touchBarVolumeDownTemplateName
        case "touchbarvolumeuptemplatename": return NSImage.touchBarVolumeUpTemplateName
        case "touchbarplayheadtemplatename": return NSImage.touchBarPlayheadTemplateName

        default:
            Log.d("IconConfiguration", "Unknown system image name: \(value)")
            return nil
        }
    }
}

// MARK: - NSColor HEX Support

extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        hex = hex.replacingOccurrences(of: "#", with: "")
        
        guard hex.count == 6 else { return nil }
        
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
