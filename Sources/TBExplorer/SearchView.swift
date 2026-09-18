import SwiftUI
import TBKit

struct SearchView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case transfers = "Transfers"
        case accounts = "Accounts"
        var id: Self { self }
    }

    struct Query: Equatable, Hashable {
        var kind: Kind
        var ledger: UInt32
        var filter: FilterFields.Parsed
        var from: UInt64
        var to: UInt64
        var reversed: Bool
        var generation: Int
    }

    @Environment(Session.self) private var session
    @Environment(Browser.self) private var browser
    @State private var idInput = ""
    @State private var idError: Error?
    @State private var isLooking = false

    @State private var kind: Kind = .transfers
    @State private var ledger = ""
    @State private var fields = FilterFields()
    @State private var useFrom = false
    @State private var useTo = false
    @State private var from = Date.now.addingTimeInterval(-86_400)
    @State private var to = Date.now
    @State private var reversed = true
    @State private var queryError: Error?
    @State private var query: Query?
    @State private var generation = 0
    @AppStorage("format.currency") private var currencyFormat = true

    @State private var accounts = PagedList<Account>()
    @State private var transfers = PagedList<Transfer>()

    var body: some View {
        VSplitView {
            Form {
                Section("Go to ID") {
                    HStack {
                        TextField("Account or transfer id", text: $idInput, prompt: Text("Paste an account or transfer id"))
                            .labelsHidden()
                            .font(.body.monospaced())
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(lookup)
                        Button("Look Up", action: lookup)
                            .disabled(UInt128(tbString: idInput) == nil || isLooking)
                    }
                    if let idError { Text(idError.localizedDescription).foregroundStyle(.red) }
                }

                Section("Query") {
                    Picker("Results", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Ledger", text: $ledger, prompt: Text("Any")).digitsOnly($ledger)
                    TextField("Code", text: $fields.code, prompt: Text("Any")).digitsOnly($fields.code)
                    TextField("user_data_128", text: $fields.userData128, prompt: Text("Any")).font(.body.monospaced())
                    TextField("user_data_64", text: $fields.userData64, prompt: Text("Any")).font(.body.monospaced())
                    TextField("user_data_32", text: $fields.userData32, prompt: Text("Any")).digitsOnly($fields.userData32)
                    HStack {
                        Toggle("From", isOn: $useFrom)
                        Spacer()
                        DatePicker("From", selection: $from, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .disabled(!useFrom)
                    }
                    HStack {
                        Toggle("To", isOn: $useTo)
                        Spacer()
                        DatePicker("To", selection: $to, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .disabled(!useTo)
                    }
                    Toggle("Newest First", isOn: $reversed)
                    CurrencyFormatToggle(isOn: $currencyFormat)
                    if let queryError { Text(queryError.localizedDescription).foregroundStyle(.red) }
                    HStack {
                        Spacer()
                        Button("Reset") {
                            ledger = ""
                            fields = FilterFields()
                            useFrom = false
                            useTo = false
                            query = nil
                        }
                        Button("Run Query", action: run)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 260, idealHeight: 470)

            Group {
                if let query {
                    switch query.kind {
                    case .accounts:
                        AccountsTable(
                            list: accounts, emptyText: "No Matching Accounts",
                            style: session.amountStyle(currency: currencyFormat))
                    case .transfers:
                        TransfersTable(
                            list: transfers, emptyText: "No Matching Transfers",
                            style: session.amountStyle(currency: currencyFormat))
                    }
                } else {
                    ContentUnavailableView("Run a Query", systemImage: "magnifyingglass",
                                           description: Text("query_accounts and query_transfers match every set field; empty fields match anything."))
                }
            }
            .frame(minHeight: 200)
        }
        .navigationTitle("Search")
        .task(id: query) { await execute() }
    }

    private func lookup() {
        isLooking = true
        idError = nil
        Task {
            do { try await browser.goTo(idInput) } catch { idError = error }
            isLooking = false
        }
    }

    private func run() {
        do {
            let parsed = try fields.parse()
            var l: UInt32 = 0
            if !ledger.isEmpty {
                guard let v = UInt32(ledger) else { throw TBError.unexpected("Ledger must be a u32.") }
                l = v
            }
            if useFrom, useTo, from > to { throw TBError.unexpected("From must be before To.") }
            generation += 1
            query = Query(
                kind: kind, ledger: l, filter: parsed,
                from: useFrom ? TBFormat.nanos(from) : 0, to: useTo ? TBFormat.nanos(to) : 0,
                reversed: reversed, generation: generation)
            queryError = nil
        } catch {
            queryError = error
        }
    }

    private func execute() async {
        guard let q = query, let client = session.client else { return }
        let base = QueryFilter(
            ledger: q.ledger, code: q.filter.code, userData128: q.filter.userData128,
            userData64: q.filter.userData64, userData32: q.filter.userData32,
            timestampMin: q.from, timestampMax: q.to, reversed: q.reversed)
        switch q.kind {
        case .accounts:
            await accounts.reset(source: QueryAccountsSource(client: client, base: base), reversed: q.reversed)
            session.observe(accounts.items)
        case .transfers:
            await transfers.reset(source: QueryTransfersSource(client: client, base: base), reversed: q.reversed)
            session.observe(transfers.items)
        }
    }
}
