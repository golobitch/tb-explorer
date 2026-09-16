import SwiftUI
import TBKit

/// Every account in the cluster: `query_accounts` with optional filters, paged by timestamp.
struct AllAccountsView: View {
    @Environment(AppModel.self) private var model
    @State private var fields = FilterFields()
    @State private var applied = FilterFields.Parsed()
    @State private var filterError: Error?
    @AppStorage("accounts.newestFirst") private var newestFirst = false
    @State private var list = PagedList<Account>()
    @State private var lookup = IDLookup()

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(fields: $fields, showsLedger: true, onApply: apply)
            if let filterError {
                ErrorBanner(error: filterError).padding(.horizontal, 12).padding(.bottom, 8)
            }
            if let message = lookup.message {
                Divider()
                LookupMessageBar(text: message) { lookup.message = nil }
            }
            Divider()
            AccountsTable(
                list: list,
                emptyText: applied == FilterFields.Parsed() ? "No Accounts" : "No Accounts Match These Filters")
        }
        .navigationTitle("Accounts")
        .navigationSubtitle("query_accounts")
        .toolbar { BrowseToolbar(newestFirst: $newestFirst) { Task { await list.reload() } } }
        .searchable(text: $lookup.text, placement: .toolbar, prompt: "Go to Account ID")
        .onSubmit(of: .search) { lookup.submit() }
        .task(id: lookup.request) { await openAccount() }
        .task(id: BrowseQuery(filter: applied, reversed: newestFirst)) {
            guard let client = model.client else { return }
            await list.reset(
                source: QueryAccountsSource(client: client, base: applied.queryFilter(reversed: newestFirst)),
                reversed: newestFirst)
            model.observe(list.items)
        }
    }

    private func apply() {
        do {
            applied = try fields.parse()
            filterError = nil
        } catch {
            filterError = error
        }
    }

    private func openAccount() async {
        guard let request = lookup.request, let client = model.client else { return }
        do {
            if let account = try await client.lookupAccounts([request.id]).first {
                model.observe([account])
                lookup.clear()
                model.open(.account(account.id))
            } else {
                lookup.message = "No account with ID \(String(request.id))."
            }
        } catch {
            lookup.message = error.localizedDescription
        }
    }
}

/// Every transfer in the cluster: `query_transfers` with optional filters, paged by timestamp.
struct AllTransfersView: View {
    @Environment(AppModel.self) private var model
    @State private var fields = FilterFields()
    @State private var applied = FilterFields.Parsed()
    @State private var filterError: Error?
    @AppStorage("transfers.newestFirst") private var newestFirst = true
    @State private var list = PagedList<Transfer>()
    @State private var lookup = IDLookup()

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(fields: $fields, showsLedger: true, onApply: apply)
            if let filterError {
                ErrorBanner(error: filterError).padding(.horizontal, 12).padding(.bottom, 8)
            }
            if let message = lookup.message {
                Divider()
                LookupMessageBar(text: message) { lookup.message = nil }
            }
            Divider()
            TransfersTable(
                list: list,
                emptyText: applied == FilterFields.Parsed() ? "No Transfers" : "No Transfers Match These Filters")
        }
        .navigationTitle("Transfers")
        .navigationSubtitle("query_transfers")
        .toolbar { BrowseToolbar(newestFirst: $newestFirst) { Task { await list.reload() } } }
        .searchable(text: $lookup.text, placement: .toolbar, prompt: "Go to Transfer ID")
        .onSubmit(of: .search) { lookup.submit() }
        .task(id: lookup.request) { await openTransfer() }
        .task(id: BrowseQuery(filter: applied, reversed: newestFirst)) {
            guard let client = model.client else { return }
            await list.reset(
                source: QueryTransfersSource(client: client, base: applied.queryFilter(reversed: newestFirst)),
                reversed: newestFirst)
            model.observe(list.items)
        }
    }

    private func apply() {
        do {
            applied = try fields.parse()
            filterError = nil
        } catch {
            filterError = error
        }
    }

    private func openTransfer() async {
        guard let request = lookup.request, let client = model.client else { return }
        do {
            if let transfer = try await client.lookupTransfers([request.id]).first {
                model.observe([transfer])
                lookup.clear()
                model.open(.transfer(transfer.id))
            } else {
                lookup.message = "No transfer with ID \(String(request.id))."
            }
        } catch {
            lookup.message = error.localizedDescription
        }
    }
}

/// Toolbar search state for "go to id". The parsed id lives in a stored `request`
/// consumed by `.task(id:)`, never captured by a closure (see `IDText`).
struct IDLookup {
    struct Request: Hashable {
        let id: UInt128
        let serial: Int
    }

    var text = ""
    var message: String?
    private(set) var request: Request?
    private var serial = 0

    mutating func submit() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let id = UInt128(tbString: raw) else {
            request = nil
            message = "“\(raw)” is not a valid ID. Use decimal or 0x-prefixed hex."
            return
        }
        serial += 1
        message = nil
        request = Request(id: id, serial: serial)
    }

    mutating func clear() {
        text = ""
        message = nil
        request = nil
    }
}

private struct BrowseQuery: Hashable {
    let filter: FilterFields.Parsed
    let reversed: Bool
}

private struct BrowseToolbar: ToolbarContent {
    @Binding var newestFirst: Bool
    let reload: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup {
            Toggle(isOn: $newestFirst) {
                Label("Newest First", systemImage: "arrow.up.arrow.down")
            }
            .help("Newest First")
            Button(action: reload) {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
        }
    }
}

private struct LookupMessageBar: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(text, systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }
}
