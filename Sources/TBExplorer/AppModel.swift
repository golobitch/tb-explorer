import Foundation
import Observation
import TBKit

enum SidebarItem: Hashable {
    case overview
    case search
    case accounts
    case transfers
    case ledger(UInt32)
}

enum Route: Hashable {
    case ledger(UInt32)
    case account(UInt128)
    case transfer(UInt128)
}

@MainActor
@Observable
final class AppModel {
    let store = ConnectionStore()
    let metadataStore = MetadataStore()

    /// Display metadata (ledger formats, code labels) for the connected cluster.
    private(set) var clusterMetadata = ClusterMetadata()

    private(set) var client: TBClient?
    private(set) var info: ClusterInfo?
    private(set) var connection: SavedConnection?

    /// TigerBeetle cannot enumerate ledgers; they are collected from everything loaded this session.
    private(set) var ledgers: [UInt32] = []

    var sidebar: SidebarItem? = .overview {
        didSet { if oldValue != sidebar { history.reset() } }
    }
    private var history = NavigationHistory<Route>()
    var isGoToPresented = false

    /// Bound to the `NavigationStack`, which also writes it directly — `adopt` reconciles that
    /// write so a route popped by its back button still becomes a forward entry. The guard is
    /// load-bearing: `@Observable` reports a mutation for any `mutating` call, even an inert one.
    var path: [Route] {
        get { history.stack }
        set {
            guard newValue != history.stack else { return }
            history.adopt(newValue)
        }
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

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
        sidebar = .overview
        history.reset()
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
    }
    #endif

    func disconnect() {
        client?.close()
        client = nil
        info = nil
        connection = nil
        clusterMetadata = ClusterMetadata()
        ledgers = []
        history.reset()
        sidebar = .overview
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

    var metadataError: String?

    func refreshLatency() async throws {
        guard let client, var info else { return }
        info.latency = try await client.ping()
        self.info = info
    }

    func select(_ item: SidebarItem) {
        sidebar = item
        history.reset()
    }

    func open(_ route: Route) {
        if case .ledger(let l) = route { observe(ledger: l) }
        history.push(route)
    }

    func goBack() {
        history.back()
    }

    func goForward() {
        history.forwardOne()
        if case .ledger(let l)? = history.stack.last { observe(ledger: l) }
    }

    /// Resolves an id to an account or transfer and navigates to it.
    func goTo(_ raw: String) async throws {
        guard let client else { return }
        guard let id = UInt128(tbString: raw) else {
            throw TBError.unexpected("“\(raw)” is not a valid u128 id.")
        }
        switch try await client.lookupID(id) {
        case .account(let a):
            observe([a])
            open(.account(a.id))
        case .transfer(let t):
            observe([t])
            open(.transfer(t.id))
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
