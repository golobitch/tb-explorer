import Foundation

/// How amounts in one ledger should read: a name, an optional symbol and the number of
/// digits after the decimal point.
public struct LedgerFormat: Codable, Hashable, Sendable {
    /// Largest exponent that still leaves a digit before the point for `UInt128.max` (39 digits).
    public static let maxExponent: UInt8 = 38

    public var name: String?
    public var symbol: String?
    public var exponent: UInt8

    public init(name: String? = nil, symbol: String? = nil, exponent: UInt8 = 0) {
        self.name = name?.isEmpty == true ? nil : name
        self.symbol = symbol?.isEmpty == true ? nil : symbol
        self.exponent = min(exponent, Self.maxExponent)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try c.decodeIfPresent(String.self, forKey: .name),
            symbol: try c.decodeIfPresent(String.self, forKey: .symbol),
            exponent: try c.decodeIfPresent(UInt8.self, forKey: .exponent) ?? 0)
    }

    /// The trailing unit shown after an amount, preferring the symbol.
    public var unit: String? { symbol ?? name }

    public init(_ currency: ISOCurrency) {
        self.init(name: currency.alpha, symbol: currency.symbol, exponent: currency.exponent)
    }
}

/// Per-connection display metadata: how each ledger's amounts read, and what the numeric
/// `code` fields mean.
///
/// Dictionaries are keyed by decimal strings so `metadata.json` stays readable and hand-editable.
public struct ClusterMetadata: Codable, Hashable, Sendable {
    public var ledgers: [String: LedgerFormat]
    public var transferCodes: [String: String]
    public var accountCodes: [String: String]

    public init(
        ledgers: [String: LedgerFormat] = [:],
        transferCodes: [String: String] = [:],
        accountCodes: [String: String] = [:]
    ) {
        self.ledgers = ledgers
        self.transferCodes = transferCodes
        self.accountCodes = accountCodes
    }

    /// Missing sections decode as empty, so a partially written or older file still loads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ledgers: try c.decodeIfPresent([String: LedgerFormat].self, forKey: .ledgers) ?? [:],
            transferCodes: try c.decodeIfPresent([String: String].self, forKey: .transferCodes) ?? [:],
            accountCodes: try c.decodeIfPresent([String: String].self, forKey: .accountCodes) ?? [:])
    }

    public subscript(ledger id: UInt32) -> LedgerFormat? {
        get { ledgers[String(id)] }
        set { ledgers[String(id)] = newValue }
    }

    public func transferCode(_ code: UInt16) -> String? { transferCodes[String(code)] }
    public func accountCode(_ code: UInt16) -> String? { accountCodes[String(code)] }

    public var isEmpty: Bool { ledgers.isEmpty && transferCodes.isEmpty && accountCodes.isEmpty }

    /// The format to use for a ledger: an explicit override first, then the ISO 4217 code
    /// matching the ledger id when `useCurrencies` is on, otherwise raw integers.
    public func format(forLedger id: UInt32, useCurrencies: Bool) -> LedgerFormat? {
        if let override = self[ledger: id] { return override }
        guard useCurrencies, let currency = ISO4217.currency(forLedger: id) else { return nil }
        return LedgerFormat(currency)
    }
}
