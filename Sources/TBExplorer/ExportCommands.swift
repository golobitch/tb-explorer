import SwiftUI
import TBKit

/// What the frontmost screen can export.
///
/// Published with `focusedSceneValue`, like `FilterFocus`, so the File menu addresses whatever is
/// in front without every screen having to wire up its own commands. Values only — never a closure
/// over an id, which is the pattern documented on `IDText`.
@MainActor
@Observable
final class ExportSource {
    var payload: ExportPayload
    /// Names the file: `tb-explorer-transfers-ledger840-20260918-2211`.
    var name: String
    /// Human-readable query, written into the JSON envelope.
    var query: String?
    /// The screen's deep link, so a reader can open where the rows came from.
    var link: String?
    /// Ledger for rows that don't carry one, i.e. balances.
    var ledger: UInt32

    let job = ExportJob()

    #if DEBUG
    /// A view's `task` can run again when the view is rebuilt; the launch-argument export runs once.
    @ObservationIgnored var debugExportRan = false
    #endif

    init(
        payload: ExportPayload, name: String, query: String? = nil, link: String? = nil,
        ledger: UInt32 = 0
    ) {
        self.payload = payload
        self.name = name
        self.query = query
        self.link = link
        self.ledger = ledger
    }

    var canScan: Bool { payload.canScan }

    #if DEBUG
    /// `-TBExport <loaded|all>:<csv|json>` writes into the app container, bypassing the save panel
    /// — the sandbox blocks writing anywhere else, and a panel cannot be clicked from a script.
    func debugExport(_ spec: String, session: Session) async -> URL? {
        let parts = spec.split(separator: ":").map(String.init)
        let scope: ExportScope = parts.first == "all" ? .all : .loaded
        let format = ExportFormat(rawValue: parts.count > 1 ? parts[1] : "csv") ?? .csv
        let url = URL(filePath: NSTemporaryDirectory()).appending(path: "export.\(format.fileExtension)")
        let choice = ExportChoice(
            url: url, format: format,
            includeFormatted: UserDefaults.standard.bool(forKey: ExportPanel.formattedKey))
        let context = ExportContext(
            metadata: session.clusterMetadata, includeFormatted: choice.includeFormatted,
            ledger: ledger, grouping: "", decimal: ".")
        let provenance = ExportProvenance(
            kind: payload.kind, clusterID: session.info?.clusterID, query: query, link: link)
        job.run(payload, scope: scope, choice: choice, context: context, provenance: provenance)
        while job.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
        return job.finished
    }
    #endif

    func export(_ scope: ExportScope, session: Session) async {
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)\(month: .twoDigits)\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)",
            timeZone: .current, calendar: .current))
        guard let choice = await ExportPanel.run(suggestedName: "\(name)-\(stamp)") else { return }

        let context = ExportContext(
            metadata: session.clusterMetadata, includeFormatted: choice.includeFormatted,
            ledger: ledger, grouping: "", decimal: ".")
        let provenance = ExportProvenance(
            kind: payload.kind, clusterID: session.info?.clusterID, query: query, link: link)
        job.run(payload, scope: scope, choice: choice, context: context, provenance: provenance)
    }
}

/// The export control every list screen puts in its toolbar.
struct ExportButton: View {
    let source: ExportSource
    @Environment(Session.self) private var session

    var body: some View {
        Menu {
            Button("Export Loaded Rows…") { run(.loaded) }
            if source.canScan {
                Button("Export All Matching…") { run(.all) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export these rows as CSV or JSON")
        .disabled(source.job.isRunning)
    }

    private func run(_ scope: ExportScope) {
        Task { await source.export(scope, session: session) }
    }
}

/// Progress while a scan is being written, and the failure if one happens. Attached once per
/// screen, next to the table it exports.
struct ExportProgressOverlay: ViewModifier {
    let job: ExportJob

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: .constant(job.isRunning)) {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Exporting \(job.rowsWritten.formatted()) rows…")
                        .monospacedDigit()
                    if let destination = job.destination {
                        Text(destination.lastPathComponent)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Cancel", role: .cancel) { job.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(24)
                .frame(width: 320)
            }
            .alert(
                "Export Failed",
                isPresented: .constant(job.error != nil),
                actions: { Button("OK") { job.dismissError() } },
                message: { Text(job.error ?? "") })
    }
}

extension View {
    /// Everything a screen needs to be exportable: the menu's view of it, the progress sheet, and
    /// in debug builds the launch-argument hook.
    func exportable(_ source: ExportSource) -> some View {
        focusedSceneValue(source)
            .modifier(ExportProgressOverlay(job: source.job))
            .modifier(DebugExportModifier(source: source))
    }
}

/// `-TBExport <kind>:<loaded|all>:<csv|json>`, e.g. `transfers:loaded:csv`. The kind has to match
/// the screen, since a navigation stack keeps the screens underneath the top one alive.
struct DebugExportModifier: ViewModifier {
    let source: ExportSource
    #if DEBUG
    @Environment(Session.self) private var session
    #endif

    func body(content: Content) -> some View {
        #if DEBUG
        content.task {
            guard let spec = UserDefaults.standard.string(forKey: "TBExport") else { return }
            let parts = spec.split(separator: ":").map(String.init)
            guard parts.first == source.payload.kind, !source.debugExportRan else { return }
            source.debugExportRan = true
            // Wait for the table to fill, the way a person would before reaching for Export; a
            // fixed delay exported an empty screen.
            for _ in 0..<80 where source.payload.loadedCount == 0 {
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard let url = await source.debugExport(parts.dropFirst().joined(separator: ":"), session: session),
                  let text = try? String(contentsOf: url, encoding: .utf8)
            else {
                print("EXPORT-FAILED:\(source.job.error ?? "no file")")
                return
            }
            // Enough for a whole test export; a full scan is checked by its byte count.
            for line in text.split(separator: "\n").prefix(5_000) { print("EXPORT:\(line)") }
            print("EXPORT-BYTES:\(text.utf8.count)")
        }
        #else
        content
        #endif
    }
}
