import Foundation
import Observation
import TBKit

/// Display metadata per saved connection, stored beside the connection list.
///
/// A separate file from `connections.json` on purpose: editing a ledger format must never put
/// the list of connections at risk.
@MainActor
@Observable
final class MetadataStore {
    private(set) var byConnection: [String: ClusterMetadata] = [:]
    private(set) var loadError: String?

    private let url = AppStorageLocation.url(for: "metadata.json")

    init() {
        load()
    }

    func load() {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            byConnection = try JSONDecoder.store.decode([String: ClusterMetadata].self, from: data)
        } catch {
            loadError = "Could not read display settings: \(error.localizedDescription)"
        }
    }

    func metadata(for connection: UUID) -> ClusterMetadata {
        byConnection[connection.uuidString] ?? ClusterMetadata()
    }

    func save(_ metadata: ClusterMetadata, for connection: UUID) throws {
        if metadata.isEmpty {
            byConnection.removeValue(forKey: connection.uuidString)
        } else {
            byConnection[connection.uuidString] = metadata
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.store.encode(byConnection).write(to: url, options: .atomic)
    }
}
