import Foundation

public enum ExportFormat: String, Sendable, CaseIterable {
    case csv
    case json

    public var fileExtension: String { rawValue }
}

/// What the export came from, written into the JSON envelope.
///
/// Ids are only unique within a cluster, so a file of rows with no cluster attached cannot be told
/// apart from the same ids somewhere else — the same reason deep links carry one.
public struct ExportProvenance: Sendable {
    public var kind: String
    public var clusterID: UInt128?
    public var query: String?
    public var link: String?
    public var exportedAt: Date

    public init(
        kind: String, clusterID: UInt128? = nil, query: String? = nil, link: String? = nil,
        exportedAt: Date = .now
    ) {
        self.kind = kind
        self.clusterID = clusterID
        self.query = query
        self.link = link
        self.exportedAt = exportedAt
    }
}

/// Builds an export one chunk at a time, so a scan of a large cluster never has to be held in
/// memory to be written. Callers write `head`, then a `row` per row, then `tail`.
public protocol ExportWriter {
    mutating func head(columns: [String]) -> String
    mutating func row(_ fields: [ExportField]) -> String
    mutating func tail() -> String
}

/// RFC 4180: values holding a comma, quote or newline are quoted, and interior quotes are doubled.
public struct CSVExportWriter: ExportWriter {
    public init() {}

    public func head(columns: [String]) -> String {
        columns.map(Self.escape).joined(separator: ",") + "\n"
    }

    public func row(_ fields: [ExportField]) -> String {
        fields.map { Self.escape($0.value.csv) }.joined(separator: ",") + "\n"
    }

    public func tail() -> String { "" }

    public static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// A single JSON document: an envelope naming the export, then the rows.
///
/// Written by hand rather than through `JSONEncoder` for one reason — every row is emitted and
/// released as it is written, so an export is bounded by the file, not by memory.
public struct JSONExportWriter: ExportWriter {
    public let provenance: ExportProvenance
    private var wroteRow = false

    public init(provenance: ExportProvenance) {
        self.provenance = provenance
    }

    public func head(columns: [String]) -> String {
        let stamp = TBFormat.iso8601(TBFormat.nanos(provenance.exportedAt))
        var envelope: [String] = [
            "  \"kind\": \(Self.string(provenance.kind))",
            "  \"exported_at\": \(Self.string(stamp))",
            "  \"exported_by\": \(Self.string("tb-explorer, tb_client \(TBClient.clientVersion)"))",
        ]
        if let cluster = provenance.clusterID {
            envelope.append("  \"cluster_id\": \(Self.string(String(cluster)))")
        }
        if let query = provenance.query { envelope.append("  \"query\": \(Self.string(query))") }
        if let link = provenance.link { envelope.append("  \"source\": \(Self.string(link))") }
        envelope.append("  \"columns\": [" + columns.map(Self.string).joined(separator: ", ") + "]")
        return "{\n" + envelope.joined(separator: ",\n") + ",\n  \"rows\": [\n"
    }

    /// The separator goes *before* each row but the first, which is what keeps the array valid
    /// without needing to know which row is last.
    public mutating func row(_ fields: [ExportField]) -> String {
        let body = fields.map { "      \(Self.string($0.name)): \(Self.value($0.value))" }
        let object = "    {\n" + body.joined(separator: ",\n") + "\n    }"
        defer { wroteRow = true }
        return (wroteRow ? ",\n" : "") + object
    }

    public func tail() -> String {
        (wroteRow ? "\n" : "") + "  ]\n}\n"
    }

    private static func value(_ value: ExportValue) -> String {
        switch value {
        case .text(let s): string(s)
        case .integer(let i): String(i)
        case .list(let names): "[" + names.map(string).joined(separator: ", ") + "]"
        }
    }

    /// Escapes per RFC 8259; control characters below 0x20 take the `\u` form.
    static func string(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

public func exportWriter(_ format: ExportFormat, provenance: ExportProvenance) -> any ExportWriter {
    switch format {
    case .csv: CSVExportWriter()
    case .json: JSONExportWriter(provenance: provenance)
    }
}

/// Renders a complete export in one call. Streaming callers use `exportWriter(_:provenance:)` and
/// drive `head`/`row`/`tail` themselves.
public func exportText<Row: ExportRow>(
    _ rows: [Row], format: ExportFormat, context: ExportContext,
    provenance: ExportProvenance = ExportProvenance(kind: Row.kind)
) -> String {
    var writer = exportWriter(format, provenance: provenance)
    // Columns come from a row of the same type, so the header always matches what follows. An
    // empty export still names its columns, using a zero row.
    var out = writer.head(columns: (rows.first ?? Row.zero).columns(context))
    for row in rows { out += writer.row(row.fields(context)) }
    return out + writer.tail()
}
