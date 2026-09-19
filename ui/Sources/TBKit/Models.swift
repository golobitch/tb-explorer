import Foundation

public struct AccountFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let linked = AccountFlags(rawValue: 1 << 0)
    public static let debitsMustNotExceedCredits = AccountFlags(rawValue: 1 << 1)
    public static let creditsMustNotExceedDebits = AccountFlags(rawValue: 1 << 2)
    public static let history = AccountFlags(rawValue: 1 << 3)
    public static let imported = AccountFlags(rawValue: 1 << 4)
    public static let closed = AccountFlags(rawValue: 1 << 5)

    static let names = [
        "linked", "debits_must_not_exceed_credits", "credits_must_not_exceed_debits",
        "history", "imported", "closed",
    ]

    /// Decoded flag names in bit order; unknown bits render as `unknown_bit_N`.
    public var names: [String] { decodeFlagNames(rawValue, Self.names) }
}

public struct TransferFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let linked = TransferFlags(rawValue: 1 << 0)
    public static let pending = TransferFlags(rawValue: 1 << 1)
    public static let postPendingTransfer = TransferFlags(rawValue: 1 << 2)
    public static let voidPendingTransfer = TransferFlags(rawValue: 1 << 3)
    public static let balancingDebit = TransferFlags(rawValue: 1 << 4)
    public static let balancingCredit = TransferFlags(rawValue: 1 << 5)
    public static let closingDebit = TransferFlags(rawValue: 1 << 6)
    public static let closingCredit = TransferFlags(rawValue: 1 << 7)
    public static let imported = TransferFlags(rawValue: 1 << 8)

    static let names = [
        "linked", "pending", "post_pending_transfer", "void_pending_transfer",
        "balancing_debit", "balancing_credit", "closing_debit", "closing_credit", "imported",
    ]

    public var names: [String] { decodeFlagNames(rawValue, Self.names) }
}

func decodeFlagNames(_ raw: UInt16, _ names: [String]) -> [String] {
    (0..<16).compactMap { bit in
        guard raw & (1 << bit) != 0 else { return nil }
        return bit < names.count ? names[bit] : "unknown_bit_\(bit)"
    }
}

public struct Account: Identifiable, Hashable, Sendable {
    public var id: UInt128
    public var debitsPending: UInt128
    public var debitsPosted: UInt128
    public var creditsPending: UInt128
    public var creditsPosted: UInt128
    public var userData128: UInt128
    public var userData64: UInt64
    public var userData32: UInt32
    public var ledger: UInt32
    public var code: UInt16
    public var flags: AccountFlags
    public var timestamp: UInt64

    /// Posted credits − posted debits.
    public var netPosted: SignedAmount { SignedAmount(credits: creditsPosted, debits: debitsPosted) }
}

public struct Transfer: Identifiable, Hashable, Sendable {
    public var id: UInt128
    public var debitAccountID: UInt128
    public var creditAccountID: UInt128
    public var amount: UInt128
    public var pendingID: UInt128
    public var userData128: UInt128
    public var userData64: UInt64
    public var userData32: UInt32
    /// Seconds; only meaningful for pending transfers.
    public var timeout: UInt32
    public var ledger: UInt32
    public var code: UInt16
    public var flags: TransferFlags
    public var timestamp: UInt64
}

public struct Balance: Identifiable, Hashable, Sendable {
    public var debitsPending: UInt128
    public var debitsPosted: UInt128
    public var creditsPending: UInt128
    public var creditsPosted: UInt128
    /// Equals the timestamp of the transfer that produced this balance.
    public var timestamp: UInt64

    public var id: UInt64 { timestamp }
    public var netPosted: SignedAmount { SignedAmount(credits: creditsPosted, debits: debitsPosted) }
}

/// Maximum events per request; stays below what a single TigerBeetle reply can carry.
public let tbMaxLimit: UInt32 = 8000
public let tbDefaultLimit: UInt32 = 100

/// `0` means "unset, use the default"; anything above the cap is clamped to it.
public func clampLimit(_ l: UInt32) -> UInt32 {
    l == 0 ? tbDefaultLimit : min(l, tbMaxLimit)
}

/// Filter for `query_accounts` / `query_transfers`. Zero values mean "any".
public struct QueryFilter: Hashable, Sendable {
    public var ledger: UInt32 = 0
    public var code: UInt16 = 0
    public var userData128: UInt128 = 0
    public var userData64: UInt64 = 0
    public var userData32: UInt32 = 0
    public var timestampMin: UInt64 = 0
    public var timestampMax: UInt64 = 0
    public var limit: UInt32 = tbDefaultLimit
    public var reversed = false

    public init(
        ledger: UInt32 = 0, code: UInt16 = 0, userData128: UInt128 = 0, userData64: UInt64 = 0,
        userData32: UInt32 = 0, timestampMin: UInt64 = 0, timestampMax: UInt64 = 0,
        limit: UInt32 = tbDefaultLimit, reversed: Bool = false
    ) {
        self.ledger = ledger
        self.code = code
        self.userData128 = userData128
        self.userData64 = userData64
        self.userData32 = userData32
        self.timestampMin = timestampMin
        self.timestampMax = timestampMax
        self.limit = limit
        self.reversed = reversed
    }
}

/// Filter for `get_account_transfers` / `get_account_balances`.
public struct AccountFilter: Hashable, Sendable {
    public var debits = true
    public var credits = true
    public var code: UInt16 = 0
    public var userData128: UInt128 = 0
    public var userData64: UInt64 = 0
    public var userData32: UInt32 = 0
    public var timestampMin: UInt64 = 0
    public var timestampMax: UInt64 = 0
    public var limit: UInt32 = tbDefaultLimit
    public var reversed = false

    public init(
        debits: Bool = true, credits: Bool = true, code: UInt16 = 0, userData128: UInt128 = 0,
        userData64: UInt64 = 0, userData32: UInt32 = 0, timestampMin: UInt64 = 0,
        timestampMax: UInt64 = 0, limit: UInt32 = tbDefaultLimit, reversed: Bool = false
    ) {
        self.debits = debits
        self.credits = credits
        self.code = code
        self.userData128 = userData128
        self.userData64 = userData64
        self.userData32 = userData32
        self.timestampMin = timestampMin
        self.timestampMax = timestampMax
        self.limit = limit
        self.reversed = reversed
    }
}

/// Timestamp cursor for paginating a TigerBeetle scan.
public enum Cursor {
    /// Bounds for the page after the item with `lastTimestamp`.
    public static func next(after lastTimestamp: UInt64, reversed: Bool) -> (min: UInt64?, max: UInt64?) {
        reversed ? (nil, lastTimestamp &- 1) : (lastTimestamp &+ 1, nil)
    }
}
