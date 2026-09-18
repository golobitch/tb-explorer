import SwiftUI
import TBKit

struct SettingsView: View {
    var body: some View {
        FormatsSettings()
            .frame(width: 620, height: 470)
    }
}

/// How amounts, ledgers and codes read: the currency switch, per-ledger overrides and code labels.
/// Overrides are stored per connection, so this pane needs a live connection to edit anything.
private struct FormatsSettings: View {
    // Rendered directly by `SettingsView`; a `TabView` returns when a second pane exists.
    @Environment(AppModel.self) private var model
    @AppStorage("format.currency") private var currencyFormat = true

    /// The amount previewed beside each ledger: 123456 reads as 1,234.56 at exponent 2.
    private static let sample: UInt128 = 123_456

    private var style: AmountStyle { model.amountStyle(currency: currencyFormat) }

    /// Ledgers seen while browsing, plus any that already carry an override.
    private var ledgers: [UInt32] {
        let overridden = model.clusterMetadata.ledgers.keys.compactMap(UInt32.init)
        return Array(Set(model.ledgers + overridden)).sorted()
    }

    var body: some View {
        Form {
            Section {
                Toggle("Format amounts as currency", isOn: $currencyFormat)
            } footer: {
                Text("""
                    Reads the ledger id as an ISO 4217 numeric code, so ledger 840 shows 123456 as \
                    1,234.56 $. Ledgers with no ISO match stay exact integers, and the exact integer \
                    is always in the tooltip.
                    """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Ledgers") {
                if model.connection == nil {
                    Text("Connect to a cluster to set per-ledger formats.").foregroundStyle(.secondary)
                } else if ledgers.isEmpty {
                    Text("Ledgers appear here as you browse.").foregroundStyle(.secondary)
                } else {
                    ForEach(ledgers, id: \.self) { ledger in
                        DisclosureGroup {
                            LedgerFormatEditor(ledger: ledger)
                        } label: {
                            HStack {
                                Text(String(ledger)).monospacedDigit()
                                Text(source(of: ledger)).foregroundStyle(.secondary)
                                Spacer()
                                Text(style.text(Self.sample, ledger: ledger))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            CodeLabels(kind: .transfer)
            CodeLabels(kind: .account)

            if let error = model.metadataError {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private func source(of ledger: UInt32) -> String {
        if model.clusterMetadata[ledger: ledger] != nil { return "Custom" }
        guard let currency = ISO4217.currency(forLedger: ledger) else { return "No ISO 4217 match" }
        return currencyFormat ? "ISO 4217 · \(currency.alpha)" : "ISO 4217 · \(currency.alpha) (off)"
    }
}

/// Name, symbol and decimals for one ledger. Empty fields mean "no override": the ISO match,
/// or exact integers, takes over again.
private struct LedgerFormatEditor: View {
    let ledger: UInt32
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var symbol = ""
    @State private var exponent = ""

    private var detected: ISOCurrency? { ISO4217.currency(forLedger: ledger) }

    private var isOverridden: Bool { model.clusterMetadata[ledger: ledger] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                labelled("Name", width: 120) {
                    TextField("Name", text: $name, prompt: Text(detected?.alpha ?? "None"))
                }
                labelled("Symbol", width: 80) {
                    TextField("Symbol", text: $symbol, prompt: Text(detected?.symbol ?? "None"))
                }
                labelled("Decimals", width: 80) {
                    TextField("Decimals", text: $exponent, prompt: Text(String(detected?.exponent ?? 0)))
                        .digitsOnly($exponent)
                }
            }
            HStack {
                Text("123456 → \(preview)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button("Remove Override", action: remove)
                    .disabled(!isOverridden)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(.vertical, 4)
        .task(id: ledger) { load() }
        .onChange(of: name) { apply() }
        .onChange(of: symbol) { apply() }
        .onChange(of: exponent) { apply() }
    }

    private var preview: String {
        TBFormat.amount(123_456 as UInt128, format: draft ?? detected.map(LedgerFormat.init))
    }

    /// The override the fields describe, or nil when they are all empty.
    private var draft: LedgerFormat? {
        guard !name.isEmpty || !symbol.isEmpty || !exponent.isEmpty else { return nil }
        let e = UInt8(exponent) ?? detected?.exponent ?? 0
        return LedgerFormat(
            name: name.isEmpty ? detected?.alpha : name,
            symbol: symbol.isEmpty ? detected?.symbol : symbol,
            exponent: e)
    }

    private func labelled<V: View>(_ title: String, width: CGFloat, @ViewBuilder _ field: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            field().labelsHidden().frame(width: width)
        }
    }

    private func load() {
        let current = model.clusterMetadata[ledger: ledger]
        name = current?.name ?? ""
        symbol = current?.symbol ?? ""
        exponent = current.map { String($0.exponent) } ?? ""
    }

    private func apply() {
        var metadata = model.clusterMetadata
        metadata[ledger: ledger] = draft
        if draft == nil { metadata.ledgers.removeValue(forKey: String(ledger)) }
        guard metadata != model.clusterMetadata else { return }
        model.updateMetadata(metadata)
    }

    private func remove() {
        name = ""
        symbol = ""
        exponent = ""
        apply()
    }
}

/// Names for the numeric `code` fields, e.g. transfer code 10 → "payment".
private struct CodeLabels: View {
    enum Kind {
        case transfer, account

        var title: String { self == .transfer ? "Transfer Codes" : "Account Codes" }
        var example: String { self == .transfer ? "payment" : "customer" }
    }

    let kind: Kind
    @Environment(AppModel.self) private var model
    @State private var newCode = ""
    @State private var newName = ""

    private var labels: [(code: UInt16, name: String)] {
        let source = kind == .transfer ? model.clusterMetadata.transferCodes : model.clusterMetadata.accountCodes
        return source.compactMap { key, value in UInt16(key).map { ($0, value) } }.sorted { $0.code < $1.code }
    }

    var body: some View {
        Section(kind.title) {
            ForEach(labels, id: \.code) { entry in
                HStack {
                    Text(String(entry.code)).monospacedDigit().frame(width: 60, alignment: .leading)
                    Text(entry.name)
                    Spacer()
                    Button { remove(entry.code) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove")
                }
            }
            HStack {
                TextField("Code", text: $newCode, prompt: Text("10"))
                    .digitsOnly($newCode)
                    .frame(width: 60)
                TextField("Name", text: $newName, prompt: Text(kind.example))
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(UInt16(newCode) == nil || newName.isEmpty)
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
        }
        .disabled(model.connection == nil)
    }

    private func add() {
        guard let code = UInt16(newCode), !newName.isEmpty else { return }
        var metadata = model.clusterMetadata
        switch kind {
        case .transfer: metadata.transferCodes[String(code)] = newName
        case .account: metadata.accountCodes[String(code)] = newName
        }
        model.updateMetadata(metadata)
        newCode = ""
        newName = ""
    }

    private func remove(_ code: UInt16) {
        var metadata = model.clusterMetadata
        switch kind {
        case .transfer: metadata.transferCodes.removeValue(forKey: String(code))
        case .account: metadata.accountCodes.removeValue(forKey: String(code))
        }
        model.updateMetadata(metadata)
    }
}
