import SwiftUI
import TBKit

struct OverviewView: View {
    @Environment(Session.self) private var session
    @Environment(Browser.self) private var browser
    @State private var isPinging = false
    @State private var pingError: Error?
    @State private var sampleError: Error?
    @State private var sampledAccounts = 0

    var body: some View {
        Form {
            if let info = session.info {
                Section("Cluster") {
                    LabeledContent("Cluster ID") {
                        HStack {
                            Text(String(info.clusterID)).monospacedDigit().textSelection(.enabled)
                            CopyButton(value: String(info.clusterID))
                        }
                    }
                    LabeledContent("Addresses") {
                        Text(info.addresses.joined(separator: ", ")).font(.body.monospaced()).textSelection(.enabled)
                    }
                    LabeledContent("Client Version") {
                        Text(info.clientVersion).monospacedDigit()
                    }
                    LabeledContent("Server Version") {
                        Text("Accepted client \(info.clientVersion)")
                            .foregroundStyle(.secondary)
                            .help("The TigerBeetle protocol does not expose the server release. A mismatch is rejected at connect.")
                    }
                    LabeledContent("Latency") {
                        HStack {
                            Text(TBFormat.latency(info.latency))
                                .monospacedDigit()
                            Button {
                                ping()
                            } label: {
                                if isPinging { ProgressView().controlSize(.mini) } else { Image(systemName: "arrow.clockwise") }
                            }
                            .buttonStyle(.borderless)
                            .help("Measure Again")
                        }
                    }
                    if let pingError { ErrorBanner(error: pingError) }
                }
            }

            Section {
                if session.ledgers.isEmpty {
                    Text("No ledgers discovered yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(session.ledgers, id: \.self) { ledger in
                        Button {
                            browser.select(.ledger(ledger))
                        } label: {
                            LabeledContent {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            } label: {
                                Label {
                                    Text("Ledger \(String(ledger))").monospacedDigit()
                                } icon: {
                                    Image(systemName: "books.vertical")
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let sampleError { ErrorBanner(error: sampleError) }
            } header: {
                Text("Discovered Ledgers")
            } footer: {
                Text("TigerBeetle has no ledger enumeration. Ledgers are collected from every account and transfer loaded this session\(sampledAccounts == Int(tbMaxLimit) ? " (initial sample capped at \(tbMaxLimit) accounts)" : ""). Add one by id in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Overview")
        .navigationSubtitle(session.connection?.name ?? "")
        .task { await sampleLedgers() }
    }

    private func ping() {
        isPinging = true
        Task {
            do {
                try await session.refreshLatency()
                pingError = nil
            } catch {
                pingError = error
            }
            isPinging = false
        }
    }

    private func sampleLedgers() async {
        guard let client = session.client else { return }
        do {
            let accounts = try await client.queryAccounts(QueryFilter(limit: tbMaxLimit))
            sampledAccounts = accounts.count
            session.observe(accounts)
        } catch {
            sampleError = error
        }
    }
}
