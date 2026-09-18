import Foundation
import Observation
import TBKit

protocol Timestamped: Identifiable, Sendable {
    var timestamp: UInt64 { get }
}

extension Account: Timestamped {}
extension Transfer: Timestamped {}

/// Source of one page of a TigerBeetle scan.
///
/// Deliberately a value type rather than a closure: a closure capturing a
/// 16-byte-aligned `UInt128` and stored in the generic `PagedList` was miscompiled,
/// so the captured account id and flags arrived corrupted at the call site and the
/// query silently returned nothing. Parameters held as stored properties are safe.
protocol PageSource<Item>: Sendable {
    associatedtype Item: Timestamped
    /// `timestampMin`/`timestampMax` are the page cursor; 0 means unbounded.
    func page(timestampMin: UInt64, timestampMax: UInt64, limit: UInt32) async throws -> [Item]
}

struct EmptySource<Item: Timestamped>: PageSource {
    func page(timestampMin: UInt64, timestampMax: UInt64, limit: UInt32) async throws -> [Item] { [] }
}

/// A single page of already-known items, e.g. a transfer found by id.
struct FixedSource<Item: Timestamped>: PageSource {
    let items: [Item]

    func page(timestampMin: UInt64, timestampMax: UInt64, limit: UInt32) async throws -> [Item] {
        timestampMin == 0 && timestampMax == 0 ? items : []
    }
}

/// Combines the query's own time range with the page cursor, keeping the tighter bound.
private func narrow(base: (min: UInt64, max: UInt64), cursor: (min: UInt64, max: UInt64)) -> (min: UInt64, max: UInt64) {
    let lower = Swift.max(base.min, cursor.min)
    let upper: UInt64 = switch (base.max, cursor.max) {
    case (0, let c): c
    case (let b, 0): b
    case (let b, let c): Swift.min(b, c)
    }
    return (lower, upper)
}

struct QueryAccountsSource: PageSource {
    let client: TBClient
    var base: QueryFilter

    func page(timestampMin: UInt64, timestampMax: UInt64, limit: UInt32) async throws -> [Account] {
        var f = base
        (f.timestampMin, f.timestampMax) = narrow(base: (base.timestampMin, base.timestampMax), cursor: (timestampMin, timestampMax))
        f.limit = limit
        return try await client.queryAccounts(f)
    }
}

struct QueryTransfersSource: PageSource {
    let client: TBClient
    var base: QueryFilter

    func page(timestampMin: UInt64, timestampMax: UInt64, limit: UInt32) async throws -> [Transfer] {
        var f = base
        (f.timestampMin, f.timestampMax) = narrow(base: (base.timestampMin, base.timestampMax), cursor: (timestampMin, timestampMax))
        f.limit = limit
        return try await client.queryTransfers(f)
    }
}

struct AccountTransfersSource: PageSource {
    let client: TBClient
    let accountID: UInt128
    var base: AccountFilter

    func page(timestampMin: UInt64, timestampMax: UInt64, limit: UInt32) async throws -> [Transfer] {
        var f = base
        (f.timestampMin, f.timestampMax) = narrow(base: (base.timestampMin, base.timestampMax), cursor: (timestampMin, timestampMax))
        f.limit = limit
        return try await client.accountTransfers(accountID, f)
    }
}

/// A TigerBeetle scan paginated by timestamp cursor. TigerBeetle has no offsets:
/// each page starts just after the previous page's last timestamp.
@MainActor
@Observable
final class PagedList<Item: Timestamped> {
    /// nil follows the user's Rows per Page setting; a caller can pin its own size instead.
    var pageSizeOverride: UInt32?

    var pageSize: UInt32 { pageSizeOverride ?? AppSettings.rowsPerPage }
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var error: Error?

    /// Readable so an export can re-run the same query without disturbing this list.
    private(set) var source: any PageSource<Item>
    private(set) var reversed: Bool
    private var generation = 0

    init(pageSize: UInt32? = nil) {
        self.pageSizeOverride = pageSize
        self.source = EmptySource<Item>()
        self.reversed = false
    }

    /// Replaces the query and loads the first page.
    func reset(source: any PageSource<Item>, reversed: Bool) async {
        self.source = source
        self.reversed = reversed
        await reload()
    }

    func reload() async {
        generation += 1
        items = []
        hasMore = true
        error = nil
        isLoading = false
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        let gen = generation
        var cursor: (min: UInt64, max: UInt64) = (0, 0)
        if let last = items.last {
            let next = Cursor.next(after: last.timestamp, reversed: reversed)
            cursor = (next.min ?? 0, next.max ?? 0)
        }
        // Read once: the setting can change between pages, and comparing a page fetched at one
        // limit against another would end the list early.
        let limit = pageSize
        do {
            let page = try await source.page(timestampMin: cursor.min, timestampMax: cursor.max, limit: limit)
            guard gen == generation else { return }
            items.append(contentsOf: page)
            hasMore = page.count == Int(limit)
        } catch {
            guard gen == generation else { return }
            self.error = error
            hasMore = false
        }
        isLoading = false
    }

    /// Call from a row's `onAppear`; loads the next page once the last row is visible.
    func loadMoreIfNeeded(after item: Item) {
        guard hasMore, !isLoading, item.id == items.last?.id else { return }
        Task { await loadMore() }
    }
}
