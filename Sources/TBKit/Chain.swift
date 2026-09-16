import Foundation

public enum PendingStatus: String, Sendable, Hashable {
    case posted, voided, expired, pending
    /// Nothing resolved it within the scanned window and the scan did not reach the account's newest transfer.
    case unknown
}

public struct PendingResolution: Sendable, Hashable {
    public var status: PendingStatus
    /// Post/void transfers that reference the pending transfer.
    public var resolutions: [Transfer]
    /// Later debit-account transfers examined.
    public var scanned: UInt32
    /// True when the scan reached the newest transfer on the debit account.
    public var exhausted: Bool
    /// Expiry in ns since epoch; nil when the pending never expires.
    public var expiresAt: UInt64?
}

public struct Chain: Sendable, Hashable {
    public var transfer: Transfer
    /// The referenced pending transfer, when `transfer` posts or voids one.
    public var pending: Transfer?
    /// Set when `transfer` or the pending it references is a pending transfer.
    public var resolution: PendingResolution?
    /// Members of the linked group containing `transfer`, in timestamp order; empty if not linked.
    public var linked: [Transfer]
}

extension TBClient {
    public static let defaultLookback: UInt32 = 1_000
    public static let maxLookback: UInt32 = 1_000_000

    /// Resolves pending → post/void relationships and the linked group for a transfer.
    public func chain(for id: UInt128, lookback: UInt32 = defaultLookback, now: Date = .now) async throws(TBError) -> Chain {
        let t = try await lookupTransfer(id)
        var chain = Chain(transfer: t, pending: nil, resolution: nil, linked: [])
        let lookback = min(max(lookback, 1), Self.maxLookback)

        var pending: Transfer? = t.flags.contains(.pending) ? t : nil
        if t.pendingID != 0, let p = try await lookupTransfers([t.pendingID]).first {
            chain.pending = p
            pending = p
        }
        if let pending {
            chain.resolution = try await resolvePending(pending, lookback: lookback, now: now)
        }

        let group = try await linkedGroup(t)
        if group.count > 1 { chain.linked = group }
        return chain
    }

    /// Post/void transfers debit the same account as the pending one and follow it in time,
    /// so scan that account's later debits for a matching `pending_id`.
    func resolvePending(_ p: Transfer, lookback: UInt32, now: Date) async throws(TBError) -> PendingResolution {
        var res = PendingResolution(status: .unknown, resolutions: [], scanned: 0, exhausted: false, expiresAt: nil)
        if p.timeout > 0 {
            res.expiresAt = p.timestamp &+ UInt64(p.timeout) &* 1_000_000_000
        }

        var cursor = p.timestamp &+ 1
        while res.scanned < lookback {
            let page = min(lookback - res.scanned, tbMaxLimit)
            let batch = try await accountTransfers(
                p.debitAccountID,
                AccountFilter(debits: true, credits: false, timestampMin: cursor, limit: page))
            res.scanned += UInt32(batch.count)
            res.resolutions.append(contentsOf: batch.filter { $0.pendingID == p.id })
            if !res.resolutions.isEmpty { break }
            if batch.count < page {
                res.exhausted = true
                break
            }
            cursor = batch[batch.count - 1].timestamp &+ 1
        }

        if res.resolutions.contains(where: { $0.flags.contains(.postPendingTransfer) }) {
            res.status = .posted
        } else if res.resolutions.contains(where: { $0.flags.contains(.voidPendingTransfer) }) {
            res.status = .voided
        } else if let exp = res.expiresAt, TBFormat.nanos(now) >= exp {
            res.status = .expired
        } else if res.exhausted {
            res.status = .pending
        }
        return res
    }

    /// Events in one batch receive consecutive timestamps and a linked chain ends at the first
    /// event without the `linked` flag. An unfiltered `query_transfers` walks the global
    /// timestamp index, so contiguity is checked against every transfer.
    func linkedGroup(_ t: Transfer) async throws(TBError) -> [Transfer] {
        var group = [t]
        let pageLimit: UInt32 = 8189 // a linked chain never exceeds one batch

        if t.timestamp > 1 {
            let before = try await queryTransfers(
                QueryFilter(timestampMin: 1, timestampMax: t.timestamp - 1, limit: pageLimit, reversed: true))
            var expect = t.timestamp - 1
            for b in before {
                guard b.timestamp == expect, b.flags.contains(.linked) else { break }
                group.append(b)
                expect -= 1
            }
        }

        if t.flags.contains(.linked) {
            let after = try await queryTransfers(QueryFilter(timestampMin: t.timestamp + 1, limit: pageLimit))
            var expect = t.timestamp + 1
            for a in after {
                guard a.timestamp == expect else { break }
                group.append(a)
                if !a.flags.contains(.linked) { break }
                expect += 1
            }
        }
        return group.sorted { $0.timestamp < $1.timestamp }
    }
}
