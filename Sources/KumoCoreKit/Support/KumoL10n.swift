import Foundation

/// Localization bundle for Kumo UI strings compiled from `Localizable.xcstrings`.
public enum KumoL10n {
    public static let bundle: Bundle = .module

    /// Resolves a String Catalog key from the Kumo resource bundle.
    public static func string(_ key: String, languageCode: String? = nil) -> String {
        if let languageCode,
           let lprojPath = bundle.path(forResource: languageCode, ofType: "lproj"),
           let languageBundle = Bundle(path: lprojPath) {
            let value = languageBundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if value != key {
                return value
            }
        }
        return String(
            localized: LocalizedStringResource(
                String.LocalizationValue(key),
                table: "Localizable",
                bundle: .atURL(bundle.bundleURL)
            )
        )
    }
}
