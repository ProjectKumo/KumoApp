import Foundation
import KumoCoreKit

/// Applies a saved language preference before SwiftUI/AppKit load localized bundles.
enum LanguageLaunchPreference {
    static func applyPersistedLanguage() {
        let prefs = UserPreferencesStore().load()
        guard let code = prefs.appLanguage else { return }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
}

private let _languageLaunchBootstrap: Void = LanguageLaunchPreference.applyPersistedLanguage()
