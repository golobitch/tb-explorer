import SwiftUI
import TBKit

struct ClusterView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            NavigationStack(path: $model.path) {
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
                Button { model.isGoToPresented = true } label: {
                    Label("Go to ID", systemImage: "number")
                }
                .help("Go to ID (⌘K)")
            }
        }
        .sheet(isPresented: $model.isGoToPresented) {
            GoToIDSheet()
        }
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch model.sidebar ?? .overview {
        case .overview: OverviewView()
        case .search: SearchView()
        case .ledger(let l): LedgerView(ledger: l).id(l)
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @State private var newLedger = ""

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Section(model.connection?.name ?? "Cluster") {
                Label("Overview", systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarItem.overview)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
            }
            Section("Ledgers") {
                if model.ledgers.isEmpty {
                    Text("Ledgers appear as you browse")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .selectionDisabled()
                }
                ForEach(model.ledgers, id: \.self) { ledger in
                    Label {
                        Text(String(ledger)).monospacedDigit()
                    } icon: {
                        Image(systemName: "books.vertical")
                    }
                    .tag(SidebarItem.ledger(ledger))
                    .contextMenu {
                        Button("Copy Ledger ID") { copyToPasteboard(String(ledger)) }
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
                    Text(model.info.map { "cluster \(String($0.clusterID))" } ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Disconnect") { model.disconnect() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            .padding(10)
        }
    }

    private func addLedger() {
        guard let l = UInt32(newLedger), l != 0 else { return }
        model.observe(ledger: l)
        model.select(.ledger(l))
        newLedger = ""
    }
}

struct GoToIDSheet: View {
    @Environment(AppModel.self) private var model
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
                try await model.goTo(input)
                dismiss()
            } catch {
                self.error = error
            }
            isLooking = false
        }
    }
}
