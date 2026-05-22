import Foundation

/// Reads available languages from the embedded String Catalog.
public func availableLocalizationsFromStringCatalog() -> [String] {
    guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings") else {
        return ["en"]
    }
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
