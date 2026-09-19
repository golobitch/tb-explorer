import SwiftUI
import TBKit

struct ConnectView: View {
    @Environment(Session.self) private var session
    @State private var selection: SavedConnection.ID?
    @State private var editing: SavedConnection?
    @State private var connecting: SavedConnection.ID?
    @State private var errors: [SavedConnection.ID: Error] = [:]
    @State private var pendingDelete: SavedConnection?

    private var store: ConnectionStore { session.store }

    var body: some View {
        HStack(spacing: 0) {
            welcome
                .frame(width: 300)
                .frame(maxHeight: .infinity)
                .background(.background.secondary)
            Divider()
            connectionList
        }
        .sheet(item: $editing) { conn in
            ConnectionEditor(connection: conn) { saved in
                try store.upsert(saved)
                selection = saved.id
            }
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let c = pendingDelete { try? store.delete(c.id) }
                pendingDelete = nil
            }
        } message: {
            Text("The saved connection is removed. The cluster is not affected.")
        }
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)
            Text("TigerBeetle Explorer")
                .font(.title2.weight(.semibold))
            Text("Read-only browser for TigerBeetle clusters")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Client \(TBClient.clientVersion)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                editing = .blank
            } label: {
                Label("New Connection…", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            // ⌘N belongs to File ▸ New Window now that the app has a window group.
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        .padding(24)
    }

    private var connectionList: some View {
        VStack(spacing: 0) {
            if store.connections.isEmpty {
                ContentUnavailableView {
                    Label("No Saved Connections", systemImage: "network.slash")
                } description: {
                    Text("Create a connection with the cluster id and replica addresses.")
                } actions: {
                    Button("New Connection…") { editing = .blank }
                }
            } else {
                List(selection: $selection) {
                    Section("Saved Connections") {
                        ForEach(store.connections) { conn in
                            ConnectionRow(
                                connection: conn,
                                isConnecting: connecting == conn.id,
                                error: errors[conn.id]
                            )
                            .tag(conn.id)
                            .contextMenu {
                                Button("Connect") { connect(conn) }
                                Button("Edit…") { editing = conn }
                                Button("Duplicate") {
                                    var copy = conn
                                    copy.id = UUID()
                                    copy.name += " Copy"
                                    copy.lastUsed = nil
                                    try? store.upsert(copy)
                                }
                                Divider()
                                Button("Delete…", role: .destructive) { pendingDelete = conn }
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: SavedConnection.ID.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first, let conn = store.connections.first(where: { $0.id == id }) {
                        connect(conn)
                    }
                }
                .onDeleteCommand {
                    pendingDelete = store.connections.first { $0.id == selection }
                }
            }
            if let loadError = store.loadError {
                Text(loadError).foregroundStyle(.red).padding()
            }
            Divider()
            HStack {
                Button { editing = .blank } label: { Image(systemName: "plus") }
                    .help("New Connection")
                Button {
                    editing = store.connections.first { $0.id == selection }
                } label: { Image(systemName: "pencil") }
                    .help("Edit Connection")
                    .disabled(selection == nil)
                Button {
                    pendingDelete = store.connections.first { $0.id == selection }
                } label: { Image(systemName: "minus") }
                    .help("Delete Connection")
                    .disabled(selection == nil)
                Spacer()
                Button("Connect") {
                    if let conn = store.connections.first(where: { $0.id == selection }) { connect(conn) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil || connecting != nil)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selection = selection ?? store.connections.first?.id }
    }

    private func connect(_ conn: SavedConnection) {
        selection = conn.id
        connecting = conn.id
        errors[conn.id] = nil
        Task {
            do {
                try await session.connect(conn)
            } catch {
                errors[conn.id] = error
            }
            connecting = nil
        }
    }
}

private struct ConnectionRow: View {
    let connection: SavedConnection
    let isConnecting: Bool
    let error: Error?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(connection.name).font(.headline)
                Text("cluster \(connection.clusterID)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if isConnecting { ProgressView().controlSize(.small) }
            }
            Text(connection.addresses.joined(separator: ", "))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            Text(connection.lastUsed.map { "Last used \($0.formatted(.relative(presentation: .named)))" } ?? "Never used")
                .font(.caption)
                .foregroundStyle(.tertiary)
            if let error {
                ConnectErrorView(error: error)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Version mismatches get both versions spelled out; the app never proceeds past one.
struct ConnectErrorView: View {
    let error: Error

    var body: some View {
        if case .versionMismatch(let client, let tooOld) = error as? TBError {
            VStack(alignment: .leading, spacing: 4) {
                Label("Client/server version mismatch", systemImage: "exclamationmark.octagon.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                    GridRow {
                        Text("Client").foregroundStyle(.secondary)
                        Text(client).monospacedDigit()
                    }
                    GridRow {
                        Text("Server").foregroundStyle(.secondary)
                        Text(tooOld ? "newer than \(client)" : "older than \(client)")
                    }
                }
                .font(.callout)
                Text("Use a TigerBeetle Explorer build whose client matches the server release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.red.opacity(0.08), in: .rect(cornerRadius: 6))
        } else {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

struct ConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var connection: SavedConnection
    let onSave: (SavedConnection) throws -> Void

    @State private var addresses: String = ""
    @State private var saveError: Error?

    init(connection: SavedConnection, onSave: @escaping (SavedConnection) throws -> Void) {
        _connection = State(initialValue: connection)
        _addresses = State(initialValue: connection.addresses.joined(separator: ", "))
        self.onSave = onSave
    }

    private var parsedAddresses: [String] {
        addresses.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var clusterValid: Bool { UInt128(tbString: connection.clusterID) != nil }
    private var isValid: Bool { !connection.name.trimmingCharacters(in: .whitespaces).isEmpty && clusterValid && !parsedAddresses.isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $connection.name, prompt: Text("Local development"))
                TextField("Cluster ID", text: $connection.clusterID, prompt: Text("0"))
                    .font(.body.monospaced())
                if !clusterValid {
                    Text("Enter a u128 as decimal or 0x-prefixed hex.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField("Replica Addresses", text: $addresses, prompt: Text("127.0.0.1:3000"), axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(1...4)
            } footer: {
                Text("Separate replica addresses with commas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let saveError {
                Text(saveError.localizedDescription).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var c = connection
                    c.name = c.name.trimmingCharacters(in: .whitespaces)
                    c.clusterID = c.clusterID.trimmingCharacters(in: .whitespaces)
                    c.addresses = parsedAddresses
                    do {
                        try onSave(c)
                        dismiss()
                    } catch {
                        saveError = error
                    }
                }
                .disabled(!isValid)
            }
        }
        .navigationTitle(connection.name.isEmpty ? "New Connection" : "Edit Connection")
    }
}
