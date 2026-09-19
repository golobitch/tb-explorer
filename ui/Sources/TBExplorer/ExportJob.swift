import Foundation
import Observation
import TBKit

/// What an export writes.
///
/// The paged cases hold the list itself rather than a copy of its rows: a table keeps loading as
/// the user scrolls, and a snapshot taken when the screen appeared would export yesterday's page.
enum ExportPayload {
    case accounts(PagedList<Account>)
    case transfers(PagedList<Transfer>)
    case balances([Balance], ledger: UInt32)

    var kind: String {
        switch self {
        case .accounts: Account.kind
        case .transfers: Transfer.kind
        case .balances: Balance.kind
        }
    }

    @MainActor var loadedCount: Int {
        switch self {
        case .accounts(let list): list.items.count
        case .transfers(let list): list.items.count
        case .balances(let rows, _): rows.count
        }
    }

    /// Whether "Export All Matching" means anything here — balances are read in one shot.
    var canScan: Bool {
        switch self {
        case .accounts, .transfers: true
        case .balances: false
        }
    }
}

enum ExportScope: Sendable {
    /// Exactly what the table holds now.
    case loaded
    /// Re-runs the query and pages to the end.
    case all
}

/// One export, from the save panel to the last row on disk.
///
/// Writes as it goes rather than building the file in memory: a scan of a large cluster is bounded
/// by the file, not by RAM. A cancelled or failed export deletes what it wrote, so a partial file
/// never passes for a complete one.
@MainActor
@Observable
final class ExportJob {
    private(set) var rowsWritten = 0
    private(set) var isRunning = false
    private(set) var destination: URL?
    private(set) var error: String?
    /// Set when an export finishes, for the "Reveal in Finder" affordance.
    private(set) var finished: URL?

    private var task: Task<Void, Never>?

    var canCancel: Bool { isRunning }

    func cancel() {
        task?.cancel()
    }

    func dismissError() {
        error = nil
    }

    func run(
        _ payload: ExportPayload, scope: ExportScope, choice: ExportChoice,
        context: ExportContext, provenance: ExportProvenance
    ) {
        guard !isRunning else { return }
        isRunning = true
        rowsWritten = 0
        error = nil
        finished = nil
        destination = choice.url

        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.write(payload, scope: scope, choice: choice, context: context, provenance: provenance)
                self.finished = choice.url
            } catch is CancellationError {
                Self.discard(choice.url)
            } catch {
                Self.discard(choice.url)
                self.error = error.localizedDescription
            }
            self.isRunning = false
            self.destination = nil
        }
    }

    private func write(
        _ payload: ExportPayload, scope: ExportScope, choice: ExportChoice,
        context: ExportContext, provenance: ExportProvenance
    ) async throws {
        let stream = try ExportStream(url: choice.url, format: choice.format, provenance: provenance)
        defer { stream.close() }

        switch payload {
        case .accounts(let list):
            try await write(
                rows: list.items, scan: list.source, reversed: list.reversed, scope: scope,
                stream: stream, context: context)
        case .transfers(let list):
            try await write(
                rows: list.items, scan: list.source, reversed: list.reversed, scope: scope,
                stream: stream, context: context)
        case .balances(let rows, _):
            try write(rows: rows, stream: stream, context: context)
        }
    }

    private func write<Row: ExportRow & Timestamped>(
        rows: [Row], scan: any PageSource<Row>, reversed: Bool, scope: ExportScope,
        stream: ExportStream, context: ExportContext
    ) async throws {
        guard scope == .all else {
            try write(rows: rows, stream: stream, context: context)
            return
        }

        try stream.head(columns: Row.zero.columns(context))
        var cursor: (min: UInt64, max: UInt64) = (0, 0)
        while true {
            try Task.checkCancellation()
            let page = try await scan.page(timestampMin: cursor.min, timestampMax: cursor.max, limit: tbMaxLimit)
            for row in page {
                try stream.row(row.fields(context))
            }
            rowsWritten += page.count
            // Same termination rule the on-screen list uses: a short page is the last one.
            guard page.count == Int(tbMaxLimit), let last = page.last else { break }
            let next = Cursor.next(after: last.timestamp, reversed: reversed)
            cursor = (next.min ?? 0, next.max ?? 0)
        }
    }

    private func write<Row: ExportRow>(rows: [Row], stream: ExportStream, context: ExportContext) throws {
        try stream.head(columns: (rows.first ?? Row.zero).columns(context))
        for row in rows {
            try stream.row(row.fields(context))
        }
        rowsWritten = rows.count
    }

    private static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A file being written a chunk at a time.
private final class ExportStream {
    private let handle: FileHandle
    private var writer: any ExportWriter
    private var wroteHead = false

    init(url: URL, format: ExportFormat, provenance: ExportProvenance) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        writer = exportWriter(format, provenance: provenance)
    }

    func head(columns: [String]) throws {
        guard !wroteHead else { return }
        wroteHead = true
        try append(writer.head(columns: columns))
    }

    func row(_ fields: [ExportField]) throws {
        try append(writer.row(fields))
    }

    func close() {
        try? append(writer.tail())
        try? handle.close()
    }

    private func append(_ text: String) throws {
        guard !text.isEmpty else { return }
        try handle.write(contentsOf: Data(text.utf8))
    }
}
