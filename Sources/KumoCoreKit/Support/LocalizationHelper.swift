import Foundation

/// Reads available languages from the embedded String Catalog.
public func availableLocalizationsFromStringCatalog() -> [String] {
    // Try the KumoCoreKit module bundle first (Swift Package standard).
    // Fall back to the main app bundle for compatibility.
    let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
        ?? Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings")
    
    guard let fileUrl = url else {
        return ["en"]
    }
    return parseLanguages(from: fileUrl)
}

private func parseLanguages(from url: URL) -> [String] {
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: [String: Any]] else {
        return ["en"]
    }

    var languages = Set<String>()
    for (_, value) in strings {
        if let localizations = value["localizations"] as? [String: Any] {
            languages.formUnion(localizations.keys)
        }
    }
    return Array(languages).sorted()
}
