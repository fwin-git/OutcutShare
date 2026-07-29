import Foundation

enum L10n {
    enum Key: String {
        case commonCancel = "common.cancel"
        case commonDone = "common.done"
        case commonLater = "common.later"
        case followActiveWindow = "follow.activeWindow"
        case followCursor = "follow.cursor"
        case followOff = "follow.off"
        case hotkeyAdjustRegion = "hotkey.adjustRegion"
        case hotkeySelectRegion = "hotkey.selectRegion"
        case hotkeyShareLastRegion = "hotkey.shareLastRegion"
        case hotkeyStopSharing = "hotkey.stopSharing"
        case hotkeyTogglePause = "hotkey.togglePause"
        case hotkeyToggleRecording = "hotkey.toggleRecording"
        case hotkeyToggleZoom = "hotkey.toggleZoom"
        case menuFollow = "menu.follow"
        case menuMoveResizeRegion = "menu.moveResizeRegion"
        case menuNoCaptures = "menu.noCaptures"
        case menuOpenRecordingsFolder = "menu.openRecordingsFolder"
        case menuOpenScreenshotsFolder = "menu.openScreenshotsFolder"
        case menuPauseSharing = "menu.pauseSharing"
        case menuPermissions = "menu.permissions"
        case menuPresets = "menu.presets"
        case menuQuit = "menu.quit"
        case menuRecentCaptures = "menu.recentCaptures"
        case menuResumeSharing = "menu.resumeSharing"
        case menuSaveCurrentRegionPreset = "menu.saveCurrentRegionPreset"
        case menuSelectRegion = "menu.selectRegion"
        case menuSettings = "menu.settings"
        case menuShareLastRegion = "menu.shareLastRegion"
        case menuShowHotbar = "menu.showHotbar"
        case menuStartRecording = "menu.startRecording"
        case menuStartVirtualMonitor = "menu.startVirtualMonitor"
        case menuStopRecording = "menu.stopRecording"
        case menuStopSharing = "menu.stopSharing"
        case menuVersion = "menu.version"
        case menuZoomInViewers = "menu.zoomInViewers"
        case menuZoomOutViewers = "menu.zoomOutViewers"
        case modifierCommand = "modifier.command"
        case modifierControl = "modifier.control"
        case modifierOption = "modifier.option"
        case modifierShift = "modifier.shift"
        case permissionsAccessibilityGranted = "permissions.accessibility.granted"
        case permissionsAccessibilityPending = "permissions.accessibility.pending"
        case permissionsAccessibilityTitle = "permissions.accessibility.title"
        case permissionsAllInPlace = "permissions.allInPlace"
        case permissionsGuide1 = "permissions.guide1"
        case permissionsGuide2 = "permissions.guide2"
        case permissionsGuide3 = "permissions.guide3"
        case permissionsOneNeeded = "permissions.oneNeeded"
        case permissionsOpenSystemSettings = "permissions.openSystemSettings"
        case permissionsReady = "permissions.ready"
        case permissionsRelaunch = "permissions.relaunch"
        case permissionsRequest = "permissions.request"
        case permissionsScreenRecordingGranted = "permissions.screenRecording.granted"
        case permissionsScreenRecordingRelaunch = "permissions.screenRecording.relaunch"
        case permissionsScreenRecordingRequired = "permissions.screenRecording.required"
        case permissionsScreenRecordingTitle = "permissions.screenRecording.title"
        case permissionsVirtualDisplayAvailable = "permissions.virtualDisplay.available"
        case permissionsVirtualDisplayTitle = "permissions.virtualDisplay.title"
        case permissionsVirtualDisplayUnavailable = "permissions.virtualDisplay.unavailable"
        case permissionsWelcome = "permissions.welcome"
        case permissionsWindowTitle = "permissions.windowTitle"
        case pickerAllApps = "picker.allApps"
        case pickerBrowse = "picker.browse"
        case pickerResults = "picker.results"
        case pickerSearch = "picker.search"
        case pickerSuggested = "picker.suggested"
        case presetDefaultName = "preset.defaultName"
        case presetFallbackName = "preset.fallbackName"
        case presetPromptMessage = "presetPrompt.message"
        case presetPromptSave = "presetPrompt.save"
        case presetPromptTitle = "presetPrompt.title"
    }

    static func string(
        _ key: Key,
        bundle: Bundle = .main,
        localeIdentifier: String? = nil,
        arguments: [CVarArg] = []
    ) -> String {
        let resolvedBundle = localizedBundle(
            in: bundle,
            localeIdentifier: localeIdentifier
        )
        let format = resolvedBundle.localizedString(
            forKey: key.rawValue,
            value: nil,
            table: "Localizable"
        )
        guard !arguments.isEmpty else { return format }
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func localizedBundle(
        in bundle: Bundle,
        localeIdentifier: String?
    ) -> Bundle {
        guard let localeIdentifier else { return bundle }
        if let localized = localizationBundle(
            in: bundle,
            localeIdentifier: localeIdentifier
        ) {
            return localized
        }
        let fallback = bundle.developmentLocalization ?? "en"
        return localizationBundle(in: bundle, localeIdentifier: fallback) ?? bundle
    }

    private static func localizationBundle(
        in bundle: Bundle,
        localeIdentifier: String
    ) -> Bundle? {
        guard let path = bundle.path(
            forResource: localeIdentifier,
            ofType: "lproj"
        ) else {
            return nil
        }
        return Bundle(path: path)
    }
}
