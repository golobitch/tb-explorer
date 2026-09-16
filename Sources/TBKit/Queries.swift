import Foundation

public enum LookupResult: Sendable, Hashable {
    case account(Account)
    case transfer(Transfer)
    case none
}

/// Result of looking up a transfer id from an account's point of view.
public enum AccountTransferMatch: Sendable, Hashable {
    /// The transfer debits or credits the account.
    case onAccount(Transfer)
    /// The transfer exists but moves funds between other accounts.
    case otherAccounts(Transfer)
    case notFound
}

public struct ClusterInfo: Sendable, Hashable {
    public var clusterID: UInt128
    public var addresses: [String]
    public var clientVersion: String
    public var latency: Duration
}

extension TBClient {
    /// Opens a client and verifies the cluster accepts it, bounding the handshake.
    public static func connect(
        clusterID: UInt128, addresses: [String], timeout: Duration = .seconds(5)
    ) async throws(TBError) -> (TBClient, ClusterInfo) {
        let client = try TBClient(clusterID: clusterID, addresses: addresses)
        do {
            let latency = try await client.ping(timeout: timeout)
            let info = ClusterInfo(
                clusterID: clusterID, addresses: addresses,
                clientVersion: clientVersion, latency: latency)
            return (client, info)
        } catch {
            client.close()
            throw error
        }
    }

    /// The first request after init includes session registration, so it is sent as a
    /// warm-up and the second round trip is timed.
    public func ping(timeout: Duration = .seconds(5)) async throws(TBError) -> Duration {
        let probe = Wire.ids([UInt128.max])
        _ = try await submit(.lookupAccounts, payload: probe, timeout: timeout)
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await submit(.lookupAccounts, payload: probe, timeout: timeout)
        return clock.now - start
    }

    public func lookupAccounts(_ ids: [UInt128]) async throws(TBError) -> [Account] {
        guard !ids.isEmpty else { return [] }
        return Wire.accounts(try await submit(.lookupAccounts, payload: Wire.ids(ids)))
    }

    public func lookupTransfers(_ ids: [UInt128]) async throws(TBError) -> [Transfer] {
        guard !ids.isEmpty else { return [] }
        return Wire.transfers(try await submit(.lookupTransfers, payload: Wire.ids(ids)))
    }

    public func lookupAccount(_ id: UInt128) async throws(TBError) -> Account {
        guard let a = try await lookupAccounts([id]).first else { throw .notFound("Account \(id)") }
        return a
    }

    public func lookupTransfer(_ id: UInt128) async throws(TBError) -> Transfer {
        guard let t = try await lookupTransfers([id]).first else { throw .notFound("Transfer \(id)") }
        return t
    }

    /// Account and transfer id spaces are independent; an account wins if both exist.
    public func lookupID(_ id: UInt128) async throws(TBError) -> LookupResult {
        if let a = try await lookupAccounts([id]).first { return .account(a) }
        if let t = try await lookupTransfers([id]).first { return .transfer(t) }
        return .none
    }

    public func queryAccounts(_ filter: QueryFilter) async throws(TBError) -> [Account] {
        Wire.accounts(try await submit(.queryAccounts, payload: Wire.encode(filter)))
    }

    public func queryTransfers(_ filter: QueryFilter) async throws(TBError) -> [Transfer] {
        Wire.transfers(try await submit(.queryTransfers, payload: Wire.encode(filter)))
    }

    public func accountTransfers(_ accountID: UInt128, _ filter: AccountFilter) async throws(TBError) -> [Transfer] {
        Wire.transfers(try await submit(.getAccountTransfers, payload: Wire.encode(filter, accountID: accountID)))
    }

    public func accountBalances(_ accountID: UInt128, _ filter: AccountFilter) async throws(TBError) -> [Balance] {
        Wire.balances(try await submit(.getAccountBalances, payload: Wire.encode(filter, accountID: accountID)))
    }

    /// Finds a transfer by id and reports whether it involves `accountID`.
    /// `get_account_transfers` cannot filter by transfer id, but a lookup is exact and O(1).
    public func findTransfer(_ id: UInt128, onAccount accountID: UInt128) async throws(TBError) -> AccountTransferMatch {
        guard let t = try await lookupTransfers([id]).first else { return .notFound }
        return t.debitAccountID == accountID || t.creditAccountID == accountID ? .onAccount(t) : .otherAccounts(t)
    }

    /// The transfer that has exactly this timestamp, e.g. the source of a balance row.
    public func transfer(atTimestamp ts: UInt64) async throws(TBError) -> Transfer? {
        try await queryTransfers(QueryFilter(timestampMin: ts, timestampMax: ts, limit: 1)).first
    }
}
