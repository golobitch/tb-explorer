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
    }

    @ViewBuilder
    private var detailRoot: some View {
        switch model.sidebar ?? .overview {
        case .overview: OverviewView()
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
