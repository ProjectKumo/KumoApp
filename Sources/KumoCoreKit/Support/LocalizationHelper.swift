import Foundation

/// Languages available for in-app selection.
///
/// Release builds ship compiled `.lproj` folders, not the source `.xcstrings`
/// file. Discovery prefers `Bundle.localizations` and `.lproj` directory names,
/// then falls back to parsing `.xcstrings` when a copy is bundled (SPM debug).
public func availableLocalizationsFromStringCatalog() -> [String] {
    var languages = Set<String>()

    for bundle in [Bundle.module, Bundle.main] {
        for code in bundle.localizations where code != "Base" {
            languages.insert(code)
        }
        languages.formUnion(lprojLanguageCodes(in: bundle))
    }

    if languages.count <= 1 {
        for bundle in [Bundle.module, Bundle.main] {
            if let url = localizableXCStringsURL(in: bundle) {
                languages.formUnion(parseLanguagesFromXCStrings(at: url))
            }
        }
    }

    languages.insert("en")
    return Array(languages).sorted()
}

private func localizableXCStringsURL(in bundle: Bundle) -> URL? {
    if let url = bundle.url(forResource: "Localizable", withExtension: "xcstrings") {
        return url
    }
    let bases = [bundle.resourceURL, bundle.bundleURL].compactMap { $0 }
    let candidates = bases.flatMap { base -> [URL] in
        [
            base.appendingPathComponent("Localizable.xcstrings"),
            base.appendingPathComponent("Contents/Resources/Localizable.xcstrings"),
        ]
    }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}

private func lprojLanguageCodes(in bundle: Bundle) -> [String] {
    let directories = resourceDirectories(in: bundle)
    var codes: [String] = []
    for directory in directories {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            continue
        }
        codes.append(contentsOf: entries.compactMap { name in
            guard name.hasSuffix(".lproj") else { return nil }
            return String(name.dropLast(6))
        })
    }
    return codes
}

private func resourceDirectories(in bundle: Bundle) -> [URL] {
    var directories: [URL] = []
    if let resourceURL = bundle.resourceURL {
        directories.append(resourceURL)
        directories.append(resourceURL.appendingPathComponent("Contents/Resources"))
    }
    if let bundleURL = bundle.bundleURL as URL? {
        directories.append(bundleURL.appendingPathComponent("Contents/Resources"))
    }
    return directories
}

private func parseLanguagesFromXCStrings(at url: URL) -> [String] {
    guard let data = try? Data(contentsOf: url),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let strings = json["strings"] as? [String: [String: Any]] else {
        return []
    }

    var languages = Set<String>()
    for value in strings.values {
        if let localizations = value["localizations"] as? [String: Any] {
            languages.formUnion(localizations.keys)
        }
    }
    return Array(languages)
}
