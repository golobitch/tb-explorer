import SwiftUI
import TBKit

/// Settings that change what the app does rather than how it reads: what to connect to at
/// launch, whether to reopen where you were, and the two query sizes.
struct GeneralSettings: View {
    @Environment(Session.self) private var session
    @AppStorage(AppSettings.startupModeKey) private var startupMode = StartupMode.ask
    @AppStorage(AppSettings.startupConnectionKey) private var startupConnection = ""
    @AppStorage(AppSettings.restoreLocationKey) private var restoreLocation = false
    @AppStorage(AppSettings.rowsPerPageKey) private var rowsPerPage = 0
    @AppStorage(AppSettings.lookbackKey) private var lookback = 0

    private static let pageSizes = [50, 100, 250, 500, 1000, 2000]
    private static let lookbacks = [1_000, 10_000, 100_000, 1_000_000]

    var body: some View {
        Form {
            Section {
                Picker("At launch", selection: $startupMode) {
                    ForEach(StartupMode.allCases) { Text($0.title).tag($0) }
                }
                if startupMode == .specific {
                    Picker("Connection", selection: $startupConnection) {
                        Text("None").tag("")
                        ForEach(session.store.connections) { Text($0.name).tag($0.id.uuidString) }
                    }
                }
                Toggle("Reopen the last location", isOn: $restoreLocation)
            } footer: {
                Text(
                    "Connecting stays a deliberate act by default: a read-only inspector should "
                        + "not reach a production cluster on its own. Reopening a location skips "
                        + "silently if the account or transfer is gone."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Rows per page", selection: $rowsPerPage) {
                    ForEach(Self.pageSizes, id: \.self) { Text($0.formatted()).tag($0) }
                }
                Picker("Pending lookback", selection: $lookback) {
                    ForEach(Self.lookbacks, id: \.self) { Text($0.formatted()).tag($0) }
                }
            } footer: {
                Text(
                    "Tables load a page at a time as you scroll, up to \(tbMaxLimit.formatted()) "
                        + "rows per request. The lookback is how far a transfer screen scans for a "
                        + "post or void before offering Search Wider."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            // An untouched setting reads as 0; show what the app actually uses.
            if rowsPerPage == 0 { rowsPerPage = Int(AppSettings.rowsPerPage) }
            if lookback == 0 { lookback = Int(AppSettings.lookback) }
        }
    }
}
