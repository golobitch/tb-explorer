import Foundation

/// Shared coders for the app's on-disk JSON: pretty-printed, stable key order and ISO-8601 dates,
/// so the files stay readable and hand-editable.
extension JSONEncoder {
    static let store: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let store: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Application Support directory for this app's stores, created on demand.
enum AppStorageLocation {
    static func url(for file: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "tb-explorer/\(file)")
    }
}
