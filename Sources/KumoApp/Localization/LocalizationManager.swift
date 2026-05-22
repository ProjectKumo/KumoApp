import Foundation
import SwiftUI
import KumoCoreKit

/// Manages the app's display language preference.
///
/// Language selection is applied via the standard `AppleLanguages` UserDefaults
/// key; a relaunch is required for the change to take full effect across the
/// entire UI. The manager also exposes the selected `Locale` for SwiftUI
/// formatting helpers.
@Observable
final class LocalizationManager {
    /// The current language preference. `nil` means "follow the system".
    var currentLanguage: String? {
        didSet {
            syncToDefaults()
        }
    }

    /// Whether the language was changed during this session and a relaunch
    /// is needed to apply it everywhere.
    var needsRestart = false

    /// Languages discovered dynamically from the String Catalog.
    var availableLanguages: [String] {
        availableLocalizationsFromStringCatalog()
    }

    /// The effective locale for formatting (dates, numbers, etc.).
    var locale: Locale {
        if let code = currentLanguage {
            return Locale(identifier: code)
        }
        return .autoupdatingCurrent
    }

    init(preferences: UserPreferences) {
        self.currentLanguage = preferences.appLanguage
        applyToDefaultsIfNeeded()
    }

    /// Returns a human-readable name for a language code in the language
    /// itself (e.g. "English", "简体中文").
    func displayName(for languageCode: String) -> String {
        let locale = Locale(identifier: languageCode)
        if let name = locale.localizedString(forIdentifier: languageCode) {
            return name
        }
        return languageCode
    }

    /// Returns the display name for the "System" / auto option.
    func systemDisplayName() -> String {
        let system = String(
            localized: "System Default",
            table: "Localizable",
            bundle: .main,
            locale: locale
        )
        if let current = currentLanguage ?? Locale.autoupdatingCurrent.language.languageCode?.identifier {
            let name = displayName(for: current)
            return "\(system) (\(name))"
        }
        return system
    }

    /// Persist the current selection back to both `UserPreferences` (via
    /// `AppleLanguages`) and mark that a restart is required.
    func selectLanguage(_ code: String?) {
        currentLanguage = code
        needsRestart = true
        syncToDefaults()
    }

    // MARK: - Private

    private func syncToDefaults() {
        if let code = currentLanguage {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }

    private func applyToDefaultsIfNeeded() {
        guard let code = currentLanguage else { return }
        UserDefaults.standard.set([code], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }
}
