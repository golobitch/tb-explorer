import Charts
import SwiftUI
import TBKit

enum AccountTab: String, CaseIterable, Identifiable {
    case transfers = "Transfers"
    case balances = "Balance History"
    case raw = "Raw"
    var id: Self { self }
}

struct AccountView: View {
    let accountID: UInt128
    @Environment(AppModel.self) private var model
    @State private var account: Account?
    @State private var error: Error?
    @AppStorage("account.tab") private var tab: AccountTab = .transfers
    @AppStorage("format.currency") private var currencyFormat = true

    var body: some View {
        Group {
            if let account {
                VStack(spacing: 0) {
                    AccountHeader(account: account, style: model.amountStyle(currency: currencyFormat))
                    Divider()
                    switch tab {
                    case .transfers: AccountTransfersTab(account: account, style: model.amountStyle(currency: currencyFormat))
                    case .balances: BalanceHistoryTab(account: account, style: model.amountStyle(currency: currencyFormat))
                    case .raw: RawView(text: account.rawDescription)
                    }
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Account Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Account \(String(accountID))")
        .navigationSubtitle(account.map { subtitle(for: $0) } ?? "")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(AccountTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup {
                CurrencyFormatToggle(isOn: $currencyFormat)
                Button { Task { await load() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r")
            }
        }
        .task(id: accountID) { await load() }
    }

    private func subtitle(for account: Account) -> String {
        let style = model.amountStyle(currency: currencyFormat)
        return "Ledger \(style.ledgerLabel(account.ledger)) · Code \(style.accountCodeLabel(account.code))"
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            let a = try await client.lookupAccount(accountID)
            account = a
            error = nil
            model.observe([a])
        } catch {
            self.error = error
        }
    }
}

private struct AccountHeader: View {
    let account: Account
    let style: AmountStyle
    @Environment(AppModel.self) private var model

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
            GridRow {
                cell("Debits Pending") { AmountText(account.debitsPending, ledger: account.ledger, style: style) }
                cell("Debits Posted") { AmountText(account.debitsPosted, ledger: account.ledger, style: style) }
                cell("Credits Pending") { AmountText(account.creditsPending, ledger: account.ledger, style: style) }
                cell("Credits Posted") { AmountText(account.creditsPosted, ledger: account.ledger, style: style) }
                cell("Net Posted (Cr − Dr)") {
                    AmountText(account.netPosted, ledger: account.ledger, style: style).font(.title3.weight(.semibold))
                }
            }
            GridRow {
                cell("ID") { HStack(spacing: 4) { IDText(id: account.id); CopyButton(value: String(account.id)) } }
                cell("Ledger") {
                    Button(style.ledgerLabel(account.ledger)) { model.open(.ledger(account.ledger)) }
                        .buttonStyle(.link)
                        .monospacedDigit()
                }
                cell("Code") { CodeText(code: account.code, kind: .account, style: style) }
                cell("Flags") { FlagsView(names: account.flags.names, emptyText: "None") }
                cell("Timestamp") { TimestampText(ns: account.timestamp) }
            }
            GridRow {
                cell("user_data_128") { IDText(id: account.userData128) }
                cell("user_data_64") { Text(String(account.userData64)).monospacedDigit().textSelection(.enabled) }
                cell("user_data_32") { Text(String(account.userData32)).monospacedDigit().textSelection(.enabled) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell<V: View>(_ title: String, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

private struct AccountTransfersTab: View {
    let account: Account
    let style: AmountStyle
    @Environment(AppModel.self) private var model
    @AppStorage("account.debits") private var debits = true
    @AppStorage("account.credits") private var credits = true
    @AppStorage("account.newestFirst") private var newestFirst = true
    @State private var list = PagedList<Transfer>()

    @State private var fields = FilterFields()
    @State private var applied = FilterFields.Parsed()
    @State private var filterError: Error?

    @State private var searchText = ""
    @State private var search: SearchState = .idle
    @State private var isSearching = false
    /// Set on submit; a `.task(id:)` performs the lookup. Keeping the id in state (read
    /// through `self`) avoids capturing a bare `UInt128` in a `Task` closure, which was
    /// miscompiled and corrupted the account id.
    @State private var searchRequest: SearchRequest?
    @State private var searchSerial = 0

    private struct SearchRequest: Hashable {
        let id: UInt128
        let serial: Int
    }

    enum SearchState: Equatable {
        case idle
        case found(Transfer)
        case elsewhere(Transfer)
        case notFound(UInt128)
        case invalid(String)
    }

    /// A transfer found by id replaces the scan in the table.
    private var pinned: Transfer? {
        if case .found(let t) = search { t } else { nil }
    }

    private var emptyText: String {
        applied == FilterFields.Parsed() ? "No Transfers" : "No Transfers Match These Filters"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Toggle("Debits", isOn: Binding(get: { debits }, set: { if $0 || credits { debits = $0 } }))
                Toggle("Credits", isOn: Binding(get: { credits }, set: { if $0 || debits { credits = $0 } }))
                Toggle("Newest First", isOn: $newestFirst)
                Spacer()
                Text(pinned == nil ? "get_account_transfers" : "lookup_transfers")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .disabled(pinned != nil)

            FilterBar(fields: $fields, onApply: applyFilters)
                .disabled(pinned != nil)
            if let filterError {
                ErrorBanner(error: filterError).padding(.horizontal, 12).padding(.bottom, 8)
            }
            if search != .idle {
                Divider()
                searchBanner
            }
            Divider()
            TransfersTable(list: list, perspective: account.id, emptyText: emptyText, style: style)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Find Transfer by ID")
        .onSubmit(of: .search, runSearch)
        .onChange(of: searchText) { _, new in
            if new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clearSearch() }
        }
        .task(id: searchRequest) { await performSearch() }
        .task(id: TransfersQuery(
            accountID: account.id, debits: debits, credits: credits, reversed: newestFirst,
            filter: applied, pinnedID: pinned?.id
        )) {
            guard let client = model.client else { return }
            if let t = pinned {
                await list.reset(source: FixedSource(items: [t]), reversed: newestFirst)
            } else {
                let f = applied
                await list.reset(
                    source: AccountTransfersSource(
                        client: client, accountID: account.id,
                        base: AccountFilter(
                            debits: debits, credits: credits, code: f.code, userData128: f.userData128,
                            userData64: f.userData64, userData32: f.userData32, reversed: newestFirst)),
                    reversed: newestFirst)
            }
            model.observe(list.items)
        }
        #if DEBUG
        .onAppear(perform: applyDebugArguments)
        #endif
    }

    @ViewBuilder
    private var searchBanner: some View {
        HStack(spacing: 8) {
            switch search {
            case .idle:
                EmptyView()
            case .found(let t):
                Label("Showing transfer \(String(t.id)) on this account", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .elsewhere(let t):
                Label(
                    "Transfer \(String(t.id)) doesn’t involve this account (\(String(t.debitAccountID)) → \(String(t.creditAccountID)))",
                    systemImage: "arrow.triangle.branch")
                    .foregroundStyle(.orange)
                RouteButton("Open Transfer", route: .transfer(t.id), open: model.open)
                    .controlSize(.small)
            case .notFound(let id):
                Label("No transfer with ID \(String(id))", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            case .invalid(let raw):
                Label("“\(raw)” is not a valid ID. Use decimal or 0x-prefixed hex.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            Spacer()
            if isSearching { ProgressView().controlSize(.small) }
            if pinned != nil {
                Button("Show All Transfers", action: clearSearch)
                    .buttonStyle(.borderless)
            }
        }
        .lineLimit(1)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }

    private func runSearch() {
        let raw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            clearSearch()
            return
        }
        guard let id = UInt128(tbString: raw) else {
            searchRequest = nil
            search = .invalid(raw)
            return
        }
        searchSerial += 1
        searchRequest = SearchRequest(id: id, serial: searchSerial)
    }

    private func performSearch() async {
        guard let request = searchRequest, let client = model.client else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            switch try await client.findTransfer(request.id, onAccount: account.id) {
            case .onAccount(let t):
                search = .found(t)
            case .otherAccounts(let t):
                search = .elsewhere(t)
                model.observe([t])
            case .notFound:
                search = .notFound(request.id)
            }
            filterError = nil
        } catch {
            search = .idle
            filterError = error
        }
    }

    private func clearSearch() {
        searchText = ""
        search = .idle
        searchRequest = nil
    }

    private func applyFilters() {
        do {
            applied = try fields.parse()
            filterError = nil
        } catch {
            filterError = error
        }
    }

    #if DEBUG
    /// `-TBSearch <id>` and `-TBFilterCode <code>` for screenshots.
    private func applyDebugArguments() {
        let defaults = UserDefaults.standard
        if let code = defaults.string(forKey: "TBFilterCode") {
            fields.code = code
            applyFilters()
        }
        if let id = defaults.string(forKey: "TBSearch") {
            searchText = id
            runSearch()
        }
    }
    #endif
}

private struct TransfersQuery: Hashable {
    let accountID: UInt128
    let debits: Bool
    let credits: Bool
    let reversed: Bool
    let filter: FilterFields.Parsed
    let pinnedID: UInt128?
}

private struct BalanceHistoryTab: View {
    let account: Account
    let style: AmountStyle
    @Environment(AppModel.self) private var model
    @State private var balances: [Balance]?
    @State private var error: Error?

    var body: some View {
        if !account.flags.contains(.history) {
            ContentUnavailableView {
                Label("No Balance History", systemImage: "clock.badge.xmark")
            } description: {
                Text("This account was created without the **history** flag. TigerBeetle only keeps balance snapshots for accounts with `flags.history`, so there is nothing to show.")
            }
        } else if let error {
            ContentUnavailableView {
                Label("Could Not Load Balances", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            }
        } else if let balances {
            if balances.isEmpty {
                ContentUnavailableView("No Balance Changes Yet", systemImage: "chart.line.flattrend.xyaxis",
                                       description: Text("History is enabled, but no transfer has touched this account."))
            } else {
                BalanceHistoryContent(balances: balances, ledger: account.ledger, style: style)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: account.id) { await load() }
        }
    }

    private func load() async {
        guard let client = model.client else { return }
        do {
            balances = try await client.accountBalances(account.id, AccountFilter(limit: tbMaxLimit))
        } catch {
            self.error = error
        }
    }
}

private struct BalancePoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
    let series: String
}

private struct BalanceHistoryContent: View {
    let balances: [Balance]
    let ledger: UInt32
    let style: AmountStyle
    @Environment(AppModel.self) private var model
    @State private var selection = Set<UInt64>()
    @State private var hoverDate: Date?

    private var points: [BalancePoint] {
        balances.flatMap { b -> [BalancePoint] in
            let d = TBFormat.date(b.timestamp)
            return [
                BalancePoint(id: "d\(b.timestamp)", date: d, value: Double(b.debitsPosted), series: "Debits Posted"),
                BalancePoint(id: "c\(b.timestamp)", date: d, value: Double(b.creditsPosted), series: "Credits Posted"),
                BalancePoint(id: "n\(b.timestamp)", date: d, value: b.netPosted.doubleValue, series: "Net"),
            ]
        }
    }

    private var hovered: Balance? {
        guard let hoverDate else { return nil }
        return balances.last { TBFormat.date($0.timestamp) <= hoverDate } ?? balances.first
    }

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if let b = hovered {
                        Text(TBFormat.timestamp(b.timestamp)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        legendValue("Debits", b.debitsPosted, .orange)
                        legendValue("Credits", b.creditsPosted, .teal)
                        HStack(spacing: 4) {
                            Text("Net").foregroundStyle(.secondary)
                            AmountText(b.netPosted, ledger: ledger, style: style)
                        }
                    } else {
                        Text("\(balances.count) snapshots · hover the chart for exact values")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if balances.count == Int(tbMaxLimit) {
                        Label("First \(tbMaxLimit) snapshots", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.callout)
                Chart(points) { p in
                    LineMark(x: .value("Time", p.date), y: .value("Amount", p.value))
                        .foregroundStyle(by: .value("Series", p.series))
                        .interpolationMethod(.stepEnd)
                    if let hoverDate {
                        RuleMark(x: .value("Selected", hoverDate))
                            .foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartForegroundStyleScale(["Debits Posted": Color.orange, "Credits Posted": Color.teal, "Net": Color.primary])
                .chartXSelection(value: $hoverDate)
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(d.formatted(.number.notation(.compactName))) }
                        }
                    }
                }
                .frame(minHeight: 220)
            }
            .padding(16)

            Table(balances.reversed(), selection: $selection) {
                TableColumn("Timestamp") { b in TimestampText(ns: b.timestamp) }
                    .width(min: 150, ideal: 220)
                TableColumn("Debits Pending") { b in
                    AmountText(b.debitsPending, ledger: ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Debits Posted") { b in
                    AmountText(b.debitsPosted, ledger: ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Credits Pending") { b in
                    AmountText(b.creditsPending, ledger: ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Credits Posted") { b in
                    AmountText(b.creditsPosted, ledger: ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Net (Cr − Dr)") { b in
                    AmountText(b.netPosted, ledger: ledger, style: style)
                        .fontWeight(.medium).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UInt64.self) { ts in
                if ts.count == 1 {
                    Button("Open Transfer") { openTransfer(at: ts.first!) }
                }
            } primaryAction: { ts in
                if let t = ts.first { openTransfer(at: t) }
            }
            .frame(minHeight: 160)
        }
    }

    private func legendValue(_ title: String, _ v: UInt128, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).foregroundStyle(.secondary)
            AmountText(v, ledger: ledger, style: style)
        }
    }

    /// A balance snapshot shares its timestamp with the transfer that produced it.
    private func openTransfer(at ts: UInt64) {
        guard let client = model.client else { return }
        Task {
            if let t = try? await client.transfer(atTimestamp: ts) { model.open(.transfer(t.id)) }
        }
    }
}

struct RawView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            CopyButton(value: text, help: "Copy All")
                .padding(12)
        }
    }
}

extension Account {
    var rawDescription: String {
        """
        id                \(id)
        debits_pending    \(debitsPending)
        debits_posted     \(debitsPosted)
        credits_pending   \(creditsPending)
        credits_posted    \(creditsPosted)
        user_data_128     \(userData128)
        user_data_64      \(userData64)
        user_data_32      \(userData32)
        ledger            \(ledger)
        code              \(code)
        flags             \(flags.rawValue)  [\(flags.names.joined(separator: ", "))]
        timestamp         \(timestamp)
        """
    }
}

extension Transfer {
    var rawDescription: String {
        """
        id                  \(id)
        debit_account_id    \(debitAccountID)
        credit_account_id   \(creditAccountID)
        amount              \(amount)
        pending_id          \(pendingID)
        user_data_128       \(userData128)
        user_data_64        \(userData64)
        user_data_32        \(userData32)
        timeout             \(timeout)
        ledger              \(ledger)
        code                \(code)
        flags               \(flags.rawValue)  [\(flags.names.joined(separator: ", "))]
        timestamp           \(timestamp)
        """
    }
}
