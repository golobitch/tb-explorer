import Foundation
import Observation
import TBKit

/// The connection to one cluster, shared by every window.
///
/// Exactly one instance may exist: `ConnectionStore` and `MetadataStore` each read their file
/// once and write it back whole, so a second session would quietly overwrite the first one's
/// edits to `connections.json` or `metadata.json`. Windows hold a `Browser` each and share this.
@MainActor
@Observable
final class Session {
    static let shared = Session()

    let store = ConnectionStore()
    let metadataStore = MetadataStore()

    /// Display metadata (ledger formats, code labels) for the connected cluster.
    private(set) var clusterMetadata = ClusterMetadata()

    private(set) var client: TBClient?
    private(set) var info: ClusterInfo?
    private(set) var connection: SavedConnection?

    /// TigerBeetle cannot enumerate ledgers; they are collected from everything loaded this session.
    private(set) var ledgers: [UInt32] = []

    /// Bumped on every connect and disconnect. Windows watch it and reset their navigation,
    /// since routes belong to the cluster they were opened from.
    private(set) var connectionToken = 0

    var metadataError: String?

    /// A link that arrived before a window could act on it. Holding it here \u{2014} rather than
    /// acting on arrival \u{2014} is what keeps a URL from ever starting a connection: nothing on
    /// this path calls `connect`, so a link can only be applied to a cluster the user connected to.
    private(set) var pendingLink: DeepLink?
    private(set) var pendingLinkCluster: UInt128?
    private(set) var pendingLinkToken = 0

    /// Explains why a link is waiting, or why it was refused.
    var linkMessage: String?

    #if DEBUG
    /// `applyDebugLaunchArguments` runs from a window's task, and there can be several windows.
    var debugArgumentsApplied = false
    #endif

    var isConnected: Bool { client != nil }

    func connect(_ saved: SavedConnection) async throws {
        guard let clusterID = UInt128(tbString: saved.clusterID) else {
            throw TBError.invalidClusterID(saved.clusterID)
        }
        disconnect()
        let (client, info) = try await TBClient.connect(clusterID: clusterID, addresses: saved.addresses)
        var used = saved
        used.lastUsed = .now
        try? store.upsert(used)
        self.client = client
        self.info = info
        self.connection = used
        clusterMetadata = metadataStore.metadata(for: used.id)
        connectionToken += 1
    }

    #if DEBUG
    /// Used by `-TBFormat`; in memory only, so screenshots never touch the saved settings.
    func adoptDebugMetadata(_ metadata: ClusterMetadata) {
        clusterMetadata = metadata
    }

    /// Used by `applyDebugLaunchArguments`; does not persist the connection.
    func adoptDebugConnection(client: TBClient, info: ClusterInfo, connection: SavedConnection) {
        disconnect()
        self.client = client
        self.info = info
        self.connection = connection
        clusterMetadata = metadataStore.metadata(for: connection.id)
        connectionToken += 1
    }
    #endif

    func disconnect() {
        client?.close()
        client = nil
        info = nil
        connection = nil
        clusterMetadata = ClusterMetadata()
        ledgers = []
        connectionToken += 1
    }

    /// How to render amounts and codes; `currency` is the user's `format.currency` setting.
    func amountStyle(currency: Bool) -> AmountStyle {
        AmountStyle(metadata: clusterMetadata, useCurrencyFormat: currency)
    }

    /// Applies edited display metadata and persists it for the active connection.
    func updateMetadata(_ metadata: ClusterMetadata) {
        clusterMetadata = metadata
        guard let id = connection?.id else { return }
        do {
            try metadataStore.save(metadata, for: id)
        } catch {
            metadataError = error.localizedDescription
        }
    }

    func refreshLatency() async throws {
        guard let client, var info else { return }
        info.latency = try await client.ping()
        self.info = info
    }

    /// Parks an incoming link. Never connects, never navigates.
    func receive(_ url: URL) {
        var cluster: UInt128?
        guard let link = DeepLink(url, cluster: &cluster) else {
            linkMessage = "\u{201C}\(url.absoluteString)\u{201D} is not a TigerBeetle Explorer link."
            return
        }
        pendingLink = link
        pendingLinkCluster = cluster
        pendingLinkToken += 1
        linkMessage = isConnected ? nil : "Connect to open \(url.absoluteString)."
    }

    /// Hands the waiting link to the first window that asks, so several windows can watch for one
    /// without any of them acting twice. A link for another cluster is refused rather than
    /// followed: ids are only unique within a cluster.
    func takePendingLink() -> DeepLink? {
        guard let link = pendingLink else { return nil }
        if let expected = pendingLinkCluster, let actual = info?.clusterID, expected != actual {
            linkMessage = "That link is for cluster \(String(expected)), and this is cluster "
                + "\(String(actual)). Connect to that cluster and open the link again."
            clearPendingLink()
            return nil
        }
        clearPendingLink()
        linkMessage = nil
        return link
    }

    private func clearPendingLink() {
        pendingLink = nil
        pendingLinkCluster = nil
    }

    /// Resolves an id to the account or transfer it names. The lookup belongs here, with the
    /// client; navigating to the result belongs to the window that asked (`Browser.goTo`).
    func resolve(_ raw: String) async throws -> Route {
        guard let client else { throw TBError.unexpected("Not connected.") }
        guard let id = UInt128(tbString: raw) else {
            throw TBError.unexpected("“\(raw)” is not a valid u128 id.")
        }
        switch try await client.lookupID(id) {
        case .account(let a):
            observe([a])
            return .account(a.id)
        case .transfer(let t):
            observe([t])
            return .transfer(t.id)
        case .none:
            throw TBError.notFound("Account or transfer \(id)")
        }
    }

    func observe(ledger: UInt32) {
        guard ledger != 0, !ledgers.contains(ledger) else { return }
        ledgers.append(ledger)
        ledgers.sort()
    }

    func observe(_ accounts: [Account]) {
        for a in accounts { observe(ledger: a.ledger) }
    }

    func observe(_ transfers: [Transfer]) {
        for t in transfers { observe(ledger: t.ledger) }
    }
}
