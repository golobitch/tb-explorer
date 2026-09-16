import Foundation
import Observation

struct SavedConnection: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// u128 as a decimal or 0x-hex string, exactly as the user entered it.
    var clusterID: String
    var addresses: [String]
    var lastUsed: Date?

    static let blank = SavedConnection(name: "", clusterID: "0", addresses: ["127.0.0.1:3000"])
}

/// Saved connections persisted as JSON in the app's Application Support directory.
@MainActor
@Observable
final class ConnectionStore {
    private(set) var connections: [SavedConnection] = []
    private(set) var loadError: String?

    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "tb-explorer/connections.json")
        load()
    }

    func load() {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            connections = try JSONDecoder.store.decode([SavedConnection].self, from: data)
            sort()
        } catch {
            loadError = "Could not read saved connections: \(error.localizedDescription)"
        }
    }

    func upsert(_ c: SavedConnection) throws {
        if let i = connections.firstIndex(where: { $0.id == c.id }) {
            connections[i] = c
        } else {
            connections.append(c)
        }
        sort()
        try save()
    }

    func delete(_ id: SavedConnection.ID) throws {
        connections.removeAll { $0.id == id }
        try save()
    }

    private func sort() {
        connections.sort { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.store.encode(connections).write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static let store: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let store: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
