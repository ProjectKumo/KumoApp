import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Indexes Kumo profiles into the system Spotlight index so users can find
/// them via Cmd+Space. Each indexed item exposes a `uniqueIdentifier` of the
/// profile id, and an associated `NSUserActivity` activity type that the app
/// delegate uses to jump back into the matching profile.
public actor SpotlightIndexer {
    public static let shared = SpotlightIndexer()

    private let domain = "io.kumo.KumoApp.profiles"
    private let activityType = "io.kumo.KumoApp.openProfile"

    public init() {}

    public func reindex(profiles: [ProfileSummary]) async {
        let index = CSSearchableIndex.default()
        // Drop the previous batch first so deleted profiles vanish from search.
        try? await deleteAllItems(in: index)
        guard !profiles.isEmpty else { return }

        let items = profiles.map { profile -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: UTType.text)
            attributes.title = profile.name
            attributes.contentDescription = profile.sourceDescription
            attributes.keywords = ["Kumo", "profile", profile.kind.rawValue]
            if let updated = profile.updatedAt {
                attributes.contentModificationDate = updated
            }
            let item = CSSearchableItem(
                uniqueIdentifier: profile.id,
                domainIdentifier: domain,
                attributeSet: attributes
            )
            return item
        }

        try? await index.indexSearchableItems(items)
    }

    public var openProfileActivityType: String { activityType }

    private func deleteAllItems(in index: CSSearchableIndex) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            index.deleteSearchableItems(withDomainIdentifiers: [domain]) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
