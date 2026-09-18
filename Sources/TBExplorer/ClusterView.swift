import SwiftUI
import TBKit

struct ClusterView: View {
    @Environment(Session.self) private var session
    @Environment(Browser.self) private var browser
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var browser = browser
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            NavigationStack(path: $browser.path) {
                detailRoot
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .ledger(let l): LedgerView(ledger: l)
                        case .account(let id): AccountView(accountID: id)
                        case .transfer(let id): TransferView(transferID: id)
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { browser.isGoToPresented = true } label: {
                    Label("Go to ID", systemImage: "number")
                }
                .help("Go to ID (⌘K)")
            }
        }
        .sheet(isPresented: $browser.isGoToPresented) {
            GoToIDSheet()
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch browser.sidebar ?? .overview {
        case .overview: OverviewView()
        case .search: SearchView()
        case .accounts: AllAccountsView()
        case .transfers: AllTransfersView()
        case .ledger(let l): LedgerView(ledger: l).id(l)
        }
    }
}

private struct Sidebar: View {
    @Environment(Session.self) private var session
    @Environment(Browser.self) private var browser
    @Environment(\.openSettings) private var openSettings
    @AppStorage("format.currency") private var currencyFormat = true
    @State private var newLedger = ""

    var body: some View {
        @Bindable var browser = browser
        List(selection: $browser.sidebar) {
            Section(session.connection?.name ?? "Cluster") {
                Label("Overview", systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarItem.overview)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
            }
            Section("Data") {
                Label("Accounts", systemImage: "person.2")
                    .tag(SidebarItem.accounts)
                Label("Transfers", systemImage: "arrow.left.arrow.right")
                    .tag(SidebarItem.transfers)
            }
            Section("Ledgers") {
                if session.ledgers.isEmpty {
                    Text("Ledgers appear as you browse")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(session.ledgers, id: \.self) { ledger in
                    Label {
                        Text(session.amountStyle(currency: currencyFormat).ledgerLabel(ledger)).monospacedDigit()
                    } icon: {
                        Image(systemName: "books.vertical")
                    }
                    .tag(SidebarItem.ledger(ledger))
                    .contextMenu {
                        Button("Copy Ledger ID") { copyToPasteboard(String(ledger)) }
                        RouteButton("Copy Link", route: .ledger(ledger), open: browser.copyLink)
                        Button("Edit Format…") { openSettings() }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Add Ledger ID", text: $newLedger)
                        .textFieldStyle(.roundedBorder)
                        .font(.callout.monospacedDigit())
                        .digitsOnly($newLedger)
                        .onSubmit(addLedger)
                    Button(action: addLedger) { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .disabled(UInt32(newLedger) == nil)
                        .help("Add Ledger")
                }
                HStack {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text(session.info.map { "cluster \(String($0.clusterID))" } ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Disconnect") { session.disconnect() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            .padding(10)
        }
    }

    private func addLedger() {
        guard let l = UInt32(newLedger), l != 0 else { return }
        session.observe(ledger: l)
        browser.select(.ledger(l))
        newLedger = ""
    }
}

struct GoToIDSheet: View {
    @Environment(Session.self) private var session
    @Environment(Browser.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var error: Error?
    @State private var isLooking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Go to ID").font(.headline)
            HStack {
                Image(systemName: "number").foregroundStyle(.secondary)
                TextField("Account or transfer id", text: $input)
                    .textFieldStyle(.plain)
                    .font(.title3.monospaced())
                    .focused($focused)
                    .onSubmit(lookup)
                if isLooking { ProgressView().controlSize(.small) }
            }
            .padding(10)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            if let error {
                Text(error.localizedDescription).font(.callout).foregroundStyle(.red)
            } else {
                Text("Decimal or 0x-hex. Detects whether the id is an account or a transfer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Go", action: lookup)
                    .keyboardShortcut(.defaultAction)
                    .disabled(UInt128(tbString: input) == nil || isLooking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            focused = true
            if let s = NSPasteboard.general.string(forType: .string), UInt128(tbString: s) != nil, s.count < 60 {
                input = s.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func lookup() {
        guard UInt128(tbString: input) != nil else { return }
        isLooking = true
        error = nil
        Task {
            do {
                try await browser.goTo(input)
                dismiss()
            } catch {
                self.error = error
            }
            isLooking = false
        }
    }
}
