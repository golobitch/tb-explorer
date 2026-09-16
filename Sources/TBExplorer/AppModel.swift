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

    private(set) var client: TBClient?
    private(set) var info: ClusterInfo?
    private(set) var connection: SavedConnection?

    /// TigerBeetle cannot enumerate ledgers; they are collected from everything loaded this session.
    private(set) var ledgers: [UInt32] = []

    var sidebar: SidebarItem? = .overview {
        didSet { if oldValue != sidebar { path = [] } }
    }
    var path: [Route] = []
    var isGoToPresented = false

    var isConnected: Bool { client != nil }

    // MARK: Connection

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
        sidebar = .overview
        path = []
    }

    func disconnect() {
        client?.close()
        client = nil
        info = nil
        connection = nil
        ledgers = []
        path = []
        sidebar = .overview
    }

    func refreshLatency() async throws {
        guard let client, var info else { return }
        info.latency = try await client.ping()
        self.info = info
    }

    // MARK: Navigation

    func select(_ item: SidebarItem) {
        sidebar = item
        path = []
    }

    func open(_ route: Route) {
        if case .ledger(let l) = route { observe(ledger: l) }
        path.append(route)
    }

    func goBack() {
        if !path.isEmpty { path.removeLast() }
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

    // MARK: Ledger discovery

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
