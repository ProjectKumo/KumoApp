import Foundation

/// Display-layer helper for inferring a country/region from a proxy node name.
///
/// The Kumo data model (`ProxyNode`) does not carry country metadata, so the
/// Overview proxy sidebar and any other UI that wants a country flag has to
/// fall back to parsing the node's `name`. Detection order:
///
/// 1. Look for an existing flag emoji (a pair of Regional Indicator Symbol
///    Letter scalars `U+1F1E6`–`U+1F1FF`) anywhere in the name.
/// 2. Match against a case-insensitive keyword table containing CJK region
///    names, common English names, and ISO 3166-1 alpha-2 codes (with
///    ASCII word boundaries so short codes like `HK` do not match inside
///    unrelated words).
///
/// All public APIs are pure value transforms — there are no SwiftUI or
/// `ProxyNode` dependencies — so callers can use this from CLI or tests too.
public enum ProxyCountry {
    /// Returns a country flag emoji parsed from the proxy node name, or `nil`
    /// when nothing matches. Callers should fall back to a generic icon
    /// (e.g. SF Symbol `globe`) when this returns `nil`.
    public static func flag(for name: String) -> String? {
        if let embedded = embeddedFlag(in: name) {
            return embedded
        }
        if let code = keywordCode(in: name) {
            return flag(forRegionCode: code)
        }
        return nil
    }

    /// Returns the inferred ISO 3166-1 alpha-2 code (e.g. `HK`, `JP`) for the
    /// node name, or `nil` when nothing matches. For names that already embed
    /// a flag emoji the code is recovered from the regional-indicator
    /// scalars.
    public static func code(for name: String) -> String? {
        if let embedded = embeddedCode(in: name) {
            return embedded
        }
        return keywordCode(in: name)
    }

    /// Returns a UI display name with embedded country flag emoji removed.
    ///
    /// The original node name remains the identity used for Mihomo API calls,
    /// selection, and search; this helper is only for surfaces that already
    /// render a separate inferred flag icon and do not want to show the same
    /// flag twice.
    public static func displayName(for name: String) -> String {
        let flagRemoval = removingEmbeddedFlags(from: name)
        guard flagRemoval.removedFlag else {
            return name
        }

        let stripped = flagRemoval.name
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: displayNameBoundarySeparators)

        return stripped.isEmpty ? name : stripped
    }

    /// Builds a flag emoji from a 2-letter ISO region code. Returns `nil` for
    /// inputs that are not exactly two ASCII letters.
    public static func flag(forRegionCode code: String) -> String? {
        let upper = code.uppercased()
        guard upper.count == 2 else {
            return nil
        }
        var scalars = String.UnicodeScalarView()
        for letter in upper.unicodeScalars {
            guard (0x41...0x5A).contains(letter.value) else {
                return nil
            }
            let value = letter.value - 0x41 + 0x1F1E6
            guard let scalar = Unicode.Scalar(value) else {
                return nil
            }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    // MARK: - Embedded flag detection

    private static func embeddedFlag(in name: String) -> String? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 2 else {
            return nil
        }
        for index in 0...(scalars.count - 2) {
            let lhs = scalars[index]
            let rhs = scalars[index + 1]
            if isRegionalIndicator(lhs), isRegionalIndicator(rhs) {
                return String(String.UnicodeScalarView([lhs, rhs]))
            }
        }
        return nil
    }

    private static func embeddedCode(in name: String) -> String? {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 2 else {
            return nil
        }
        for index in 0...(scalars.count - 2) {
            let lhs = scalars[index]
            let rhs = scalars[index + 1]
            if isRegionalIndicator(lhs), isRegionalIndicator(rhs) {
                return "\(letter(fromIndicator: lhs))\(letter(fromIndicator: rhs))"
            }
        }
        return nil
    }

    private static func removingEmbeddedFlags(from name: String) -> (name: String, removedFlag: Bool) {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count >= 2 else {
            return (name, false)
        }

        var result = String.UnicodeScalarView()
        var removedFlag = false
        var index = 0
        while index < scalars.count {
            if index + 1 < scalars.count,
               isRegionalIndicator(scalars[index]),
               isRegionalIndicator(scalars[index + 1]) {
                removedFlag = true
                index += 2
                continue
            }
            result.append(scalars[index])
            index += 1
        }
        return (String(result), removedFlag)
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F1E6...0x1F1FF).contains(scalar.value)
    }

    private static func letter(fromIndicator scalar: Unicode.Scalar) -> Character {
        let value = scalar.value - 0x1F1E6 + 0x41
        return Character(Unicode.Scalar(value)!)
    }

    private static let displayNameBoundarySeparators = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "-_·•/|｜"))

    // MARK: - Keyword matching

    /// Two-phase match against the keyword data:
    ///
    /// 1. Long keywords (≥ 3 ASCII chars, or any CJK length) — ICU localized
    ///    region names plus manual aliases. The table is pre-sorted by
    ///    keyword length descending so that `"Hong Kong"` wins over `"HK"`
    ///    and `"United States"` wins over `"US"`.
    /// 2. 2-letter ISO codes — `name` is split into ASCII letter tokens and
    ///    scanned left-to-right; the first token that resolves to a known
    ///    region wins. This disambiguates names like `"us-la-02"` toward
    ///    `US` because the `us` token appears before `la` (Laos), instead
    ///    of relying on the alphabetical order of ISO codes in a flat list.
    private static func keywordCode(in name: String) -> String? {
        for entry in longKeywordTable where entry.matches(name) {
            return entry.code
        }
        for token in asciiLetterTokens(in: name) where token.count == 2 {
            if let code = isoCodeLookup[token.uppercased()] {
                return code
            }
        }
        return nil
    }

    private static func asciiLetterTokens(in name: String) -> [Substring] {
        name.split(whereSeparator: { !($0.isASCII && $0.isLetter) })
    }

    private struct KeywordEntry {
        let keyword: String
        let code: String
        let requiresAsciiBoundary: Bool

        func matches(_ name: String) -> Bool {
            if requiresAsciiBoundary {
                let pattern = "(?<![A-Za-z0-9])\(NSRegularExpression.escapedPattern(for: keyword))(?![A-Za-z0-9])"
                return name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
            }
            return name.localizedCaseInsensitiveContains(keyword)
        }
    }

    // MARK: Keyword sources

    /// Seed locales whose `localizedString(forRegionCode:)` output feeds the
    /// keyword table. The list intentionally covers English plus the
    /// languages most commonly seen in proxy node naming (Simplified /
    /// Traditional Chinese, Japanese). Adding more locales is safe — the
    /// table dedupes on `(lowercased keyword, code)`.
    private static let seedLocales: [Locale] = [
        Locale(identifier: "en_US"),
        Locale(identifier: "zh_Hans_CN"),
        Locale(identifier: "zh_Hant_HK"),
        Locale(identifier: "ja_JP")
    ]

    /// Colloquial aliases that Foundation/ICU does not provide. Keep small
    /// and conservative — only entries that real subscriptions tend to use:
    ///
    /// - English shorthands ICU does not return: `USA`, `UK`, `Britain`,
    ///   `England`.
    /// - HK / TW short Chinese names: ICU in `zh_Hans_CN` returns politically
    ///   formal forms like `中国香港特别行政区` / `中国台湾`, which never
    ///   substring-match user names like `香港 01`.
    /// - Singapore: ICU returns `新加坡`, but `狮城` / `獅城` show up often
    ///   enough in subscription naming to be worth adding.
    ///
    /// 2-letter ASCII entries (e.g. `UK`) feed `isoCodeLookup` so they
    /// participate in Phase 2 position-based matching; everything else feeds
    /// `longKeywordTable`.
    private static let manualAliases: [(keyword: String, code: String)] = [
        ("USA", "US"),
        ("UK", "GB"),
        ("Britain", "GB"),
        ("England", "GB"),
        ("香港", "HK"),
        ("台湾", "TW"),
        ("台灣", "TW"),
        ("臺灣", "TW"),
        ("狮城", "SG"),
        ("獅城", "SG")
    ]

    /// All ISO 3166-1 alpha-2 region codes Foundation knows about. Filtered
    /// to two-letter ASCII identifiers so subdivisions / macro-regions are
    /// excluded.
    private static let isoRegionCodes: [String] = {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { identifier in
                identifier.count == 2 && identifier.allSatisfy { $0.isASCII && $0.isLetter }
            }
    }()

    /// Phase 1 table: long keywords (CJK names, English long names, multi-char
    /// aliases). Sorted by keyword length descending so the most specific
    /// match wins first. 2-letter ASCII entries are intentionally excluded —
    /// they live in `isoCodeLookup` and participate in Phase 2 instead.
    private static let longKeywordTable: [KeywordEntry] = buildLongKeywordTable()

    /// Phase 2 lookup: 2-letter ISO region codes (uppercase) → canonical
    /// ISO code. Seeded from `Locale.Region.isoRegions` and supplemented by
    /// any 2-letter ASCII entries in `manualAliases` (e.g. `UK → GB`).
    private static let isoCodeLookup: [String: String] = buildIsoCodeLookup()

    private static func buildLongKeywordTable() -> [KeywordEntry] {
        var entries: [KeywordEntry] = []
        var seen = Set<String>()

        func add(_ raw: String, code: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let isAscii = trimmed.unicodeScalars.allSatisfy(\.isASCII)
            // Skip 2-letter ASCII keywords — they go through Phase 2 so we
            // can pick the *first* token in the node name, avoiding random
            // ambiguity between e.g. LA (Laos) and US.
            guard !(isAscii && trimmed.count == 2) else { return }
            let dedupKey = "\(trimmed.lowercased())|\(code)"
            guard seen.insert(dedupKey).inserted else { return }
            entries.append(KeywordEntry(
                keyword: trimmed,
                code: code,
                requiresAsciiBoundary: isAscii
            ))
        }

        for alias in manualAliases {
            add(alias.keyword, code: alias.code)
        }

        for code in isoRegionCodes {
            for locale in seedLocales {
                guard let localized = locale.localizedString(forRegionCode: code) else {
                    continue
                }
                // Skip cases where ICU has no real localization and just
                // echoed the code back; Phase 2 covers raw codes.
                guard localized.caseInsensitiveCompare(code) != .orderedSame else {
                    continue
                }
                add(localized, code: code)
            }
        }

        return entries.sorted { lhs, rhs in
            lhs.keyword.count > rhs.keyword.count
        }
    }

    private static func buildIsoCodeLookup() -> [String: String] {
        var lookup: [String: String] = [:]
        for code in isoRegionCodes {
            let upper = code.uppercased()
            lookup[upper] = upper
        }
        for alias in manualAliases where alias.keyword.count == 2
            && alias.keyword.unicodeScalars.allSatisfy(\.isASCII) {
            lookup[alias.keyword.uppercased()] = alias.code.uppercased()
        }
        return lookup
    }
}
