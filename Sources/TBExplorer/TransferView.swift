import SwiftUI
import TBKit

struct TransferView: View {
    let transferID: UInt128
    @Environment(AppModel.self) private var model
    @State private var chain: Chain?
    @State private var error: Error?
    @State private var lookback = TBClient.defaultLookback
    @State private var isLoading = false
    @State private var showRaw = false
    @AppStorage("format.currency") private var currencyFormat = true

    private var style: AmountStyle { model.amountStyle(currency: currencyFormat) }

    var body: some View {
        Group {
            if let chain {
                Form {
                    TransferSections(transfer: chain.transfer, style: style)
                    ChainSections(chain: chain, style: style, lookback: lookback, isLoading: isLoading) {
                        lookback = min(lookback * 10, TBClient.maxLookback)
                    }
                    Section("Raw") {
                        DisclosureGroup("All Fields", isExpanded: $showRaw) {
                            HStack(alignment: .top) {
                                Text(chain.transfer.rawDescription)
                                    .font(.body.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                CopyButton(value: chain.transfer.rawDescription, help: "Copy All")
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else if let error {
                ContentUnavailableView {
                    Label("Transfer Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Transfer \(String(transferID))")
        .navigationSubtitle(chain.map { subtitle(for: $0.transfer) } ?? "")
        .toolbar {
            ToolbarItemGroup {
                CurrencyFormatToggle(isOn: $currencyFormat)
                Button { Task { await load() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }
        }
        .task(id: "\(transferID)/\(lookback)") { await load() }
    }

    private func subtitle(for transfer: Transfer) -> String {
        "Ledger \(style.ledgerLabel(transfer.ledger)) · Code \(style.transferCodeLabel(transfer.code))"
    }

    private func load() async {
        guard let client = model.client else { return }
        isLoading = true
        do {
            let c = try await client.chain(for: transferID, lookback: lookback)
            chain = c
            error = nil
            model.observe([c.transfer] + c.linked + (c.pending.map { [$0] } ?? []))
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

private struct TransferSections: View {
    let transfer: Transfer
    let style: AmountStyle
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            HStack(spacing: 16) {
                accountCell("Debit Account", transfer.debitAccountID, .orange)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                accountCell("Credit Account", transfer.creditAccountID, .teal)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Amount").font(.caption).foregroundStyle(.secondary)
                    AmountText(transfer.amount, ledger: transfer.ledger, style: style)
                        .font(.title2.weight(.semibold))
                }
            }
            .padding(.vertical, 4)
        }

        Section("Details") {
            LabeledContent("ID") { HStack { IDText(id: transfer.id); CopyButton(value: String(transfer.id)) } }
            LabeledContent("Flags") { FlagsView(names: transfer.flags.names, emptyText: "None") }
            LabeledContent("Pending ID") {
                if transfer.pendingID == 0 { Text("—").foregroundStyle(.tertiary) } else {
                    IDText(id: transfer.pendingID, route: .transfer(transfer.pendingID), open: model.open)
                }
            }
            LabeledContent("Timeout") {
                Text(transfer.timeout == 0 ? "—" : Duration.seconds(transfer.timeout).formatted(.units(allowed: [.hours, .minutes, .seconds])))
                    .monospacedDigit()
            }
            LabeledContent("Ledger") {
                Button(style.ledgerLabel(transfer.ledger)) { model.open(.ledger(transfer.ledger)) }
                    .buttonStyle(.link)
            }
            LabeledContent("Code") { CodeText(code: transfer.code, kind: .transfer, style: style) }
            LabeledContent("user_data_128") { IDText(id: transfer.userData128) }
            LabeledContent("user_data_64") { Text(String(transfer.userData64)).monospacedDigit().textSelection(.enabled) }
            LabeledContent("user_data_32") { Text(String(transfer.userData32)).monospacedDigit().textSelection(.enabled) }
            LabeledContent("Timestamp") { TimestampText(ns: transfer.timestamp) }
        }
    }

    private func accountCell(_ title: String, _ id: UInt128, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(tint)
            IDText(id: id, route: .account(id), open: model.open)
        }
    }
}

private struct ChainSections: View {
    let chain: Chain
    let style: AmountStyle
    let lookback: UInt32
    let isLoading: Bool
    let onSearchWider: () -> Void

    private var t: Transfer { chain.transfer }

    var body: some View {
        if chain.pending == nil, chain.resolution == nil, chain.linked.isEmpty {
            Section("Chain") {
                Text("Single-phase transfer, not part of a linked group.").foregroundStyle(.secondary)
            }
        }

        if let pending = chain.pending {
            Section(t.flags.contains(.voidPendingTransfer) ? "Voids Pending Transfer" : "Posts Pending Transfer") {
                TransferRow(transfer: pending, style: style)
            }
        }

        if let res = chain.resolution {
            Section {
                LabeledContent("Status") { StatusBadge(status: res.status) }
                if let exp = res.expiresAt {
                    LabeledContent(res.status == .expired ? "Expired At" : "Expires At") { TimestampText(ns: exp) }
                } else if t.flags.contains(.pending) {
                    LabeledContent("Expires") { Text("Never").foregroundStyle(.secondary) }
                }
                if t.flags.contains(.pending) {
                    ForEach(res.resolutions) { TransferRow(transfer: $0, style: style) }
                }
                LabeledContent("Scanned") {
                    Text("\(res.scanned) later debit-account transfers\(res.exhausted ? " (all)" : "")")
                        .foregroundStyle(.secondary)
                }
                if res.status == .unknown {
                    HStack {
                        Text("No post or void found within a lookback of \(lookback.formatted()).")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Search Wider", action: onSearchWider)
                            .disabled(isLoading || lookback >= TBClient.maxLookback)
                        if isLoading { ProgressView().controlSize(.small) }
                    }
                }
            } header: {
                Text(t.flags.contains(.pending) ? "Pending Status" : "Pending Transfer Status")
            } footer: {
                if res.status == .expired {
                    Text("Expiry is derived from the timeout: no post or void was found and the timeout has elapsed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        if !chain.linked.isEmpty {
            Section("Linked Group · \(chain.linked.count) Transfers") {
                ForEach(chain.linked) { TransferRow(transfer: $0, isCurrent: $0.id == t.id, style: style) }
            }
        }
    }
}

struct TransferRow: View {
    let transfer: Transfer
    var isCurrent = false
    var style: AmountStyle = .raw
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "arrowtriangle.right.fill" : "arrow.left.arrow.right")
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                if isCurrent {
                    IDText(id: transfer.id)
                } else {
                    IDText(id: transfer.id, route: .transfer(transfer.id), open: model.open)
                }
                TimestampText(ns: transfer.timestamp).font(.caption)
            }
            Spacer()
            FlagsView(names: transfer.flags.names, emptyText: "No flags")
            AmountText(transfer.amount, ledger: transfer.ledger, style: style)
                .frame(minWidth: 90, alignment: .trailing)
        }
    }
}
