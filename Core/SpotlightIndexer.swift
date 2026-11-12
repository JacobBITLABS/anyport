import CoreSpotlight
import UniformTypeIdentifiers
import AppKit

enum SpotlightIndexer {
    private static let domain = "com.jacobnielsen.sshportbar.hosts"

    static func reindexHosts(_ hosts: [SSHHost]) {
        let thumbnail = appIconThumbnail()
        let items: [CSSearchableItem] = hosts.map { host in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = host.alias
            attributes.contentDescription = host.displaySubtitle
            attributes.keywords = [host.alias, "ssh", "anyport"]
            attributes.displayName = host.alias
            if let thumbnail {
                attributes.thumbnailData = thumbnail
            }

            return CSSearchableItem(
                uniqueIdentifier: host.alias,
                domainIdentifier: domain,
                attributeSet: attributes
            )
        }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            let status: String
            if let error {
                status = "ERROR \(error.localizedDescription)"
            } else {
                let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                status = "OK \(items.count) items at \(time)"
            }
            UserDefaults.standard.set(status, forKey: "spotlight_index_status")
        }
    }

    static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
    }

    /// App icon as the Spotlight result thumbnail, so hosts are recognizable.
    private static func appIconThumbnail() -> Data? {
        guard let image = NSApp?.applicationIconImage else { return nil }
        return image.tiffRepresentation
    }
}
