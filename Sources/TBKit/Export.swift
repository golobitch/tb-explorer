import Foundation

/// One exported value, typed so CSV and JSON can disagree about how to render it.
///
/// A `u128` never becomes a JSON number: the largest exactly representable JSON integer is 2^53,
/// so an id written as a number comes back with its low digits rewritten. Ids, amounts and
/// timestamps are therefore text everywhere, and only values that genuinely fit — ledger, code,
/// the 32-bit user data, a timeout in seconds — stay numeric.
public enum ExportValue: Sendable, Equatable {
    case text(String)
    case integer(Int)
    case list([String])

    /// How the value reads in a CSV cell. A list joins with spaces, since the field separator is
    /// a comma and quoting a comma-joined list reads worse than it looks.
    public var csv: String {
        switch self {
        case .text(let s): s
        case .integer(let i): String(i)
        case .list(let names): names.joined(separator: " ")
        }
    }
}

public struct ExportField: Sendable, Equatable {
    public let name: String
    public let value: ExportValue

    public init(_ name: String, _ value: ExportValue) {
        self.name = name
        self.value = value
    }

    public init(_ name: String, _ text: String) {
        self.init(name, .text(text))
    }
}

/// Everything a row needs to describe itself that it doesn't carry: how to read its ledger, and
/// whether the reader asked for the readable companion columns.
public struct ExportContext: Sendable {
    public var metadata: ClusterMetadata
    /// Opt-in per export. Off means exact integers only — the file is then the same whatever the
    /// window happened to be showing.
    public var includeFormatted: Bool
    /// Applied to rows that carry no ledger of their own, i.e. balances.
    public var ledger: UInt32
    /// Fixed rather than taken from `Locale`, so a file never depends on the machine that wrote it.
    public var grouping: String
    public var decimal: String

    public init(
        metadata: ClusterMetadata = ClusterMetadata(),
        includeFormatted: Bool = false,
        ledger: UInt32 = 0,
        grouping: String = "",
        decimal: String = "."
    ) {
        self.metadata = metadata
        self.includeFormatted = includeFormatted
        self.ledger = ledger
        self.grouping = grouping
        self.decimal = decimal
    }

    func format(_ ledger: UInt32) -> LedgerFormat? {
        metadata.format(forLedger: ledger, useCurrencies: true)
    }

    /// The readable companion for an amount, or nil when the ledger has no format — in which case
    /// the column is left out entirely rather than repeating the exact value under another name.
    func formatted(_ v: UInt128, ledger: UInt32) -> String? {
        guard includeFormatted, let format = format(ledger) else { return nil }
        return TBFormat.amount(v, format: format, grouping: grouping, decimal: decimal)
    }

    func formatted(_ v: SignedAmount, ledger: UInt32) -> String? {
        guard includeFormatted, let format = format(ledger) else { return nil }
        return TBFormat.amount(v, format: format, grouping: grouping, decimal: decimal)
    }

    func ledgerName(_ ledger: UInt32) -> String? {
        guard includeFormatted else { return nil }
        return format(ledger)?.name
    }

    func codeLabel(_ code: UInt16, transfer: Bool) -> String? {
        guard includeFormatted else { return nil }
        return transfer ? metadata.transferCode(code) : metadata.accountCode(code)
    }
}

/// A row that can be written to CSV or JSON.
///
/// `fields` is the single source of truth: the header comes from the same call, so a file can
/// never gain a column without a value or the reverse.
public protocol ExportRow: Sendable {
    static var kind: String { get }
    /// An all-zero row, used only to name the columns of an export that has none.
    static var zero: Self { get }
    func fields(_ context: ExportContext) -> [ExportField]
}

extension ExportRow {
    public func columns(_ context: ExportContext) -> [String] {
        fields(context).map(\.name)
    }
}

extension Account: ExportRow {
    public static var kind: String { "accounts" }

    public static var zero: Account {
        Account(
            id: 0, debitsPending: 0, debitsPosted: 0, creditsPending: 0, creditsPosted: 0,
            userData128: 0, userData64: 0, userData32: 0, ledger: 0, code: 0,
            flags: AccountFlags(rawValue: 0), timestamp: 0)
    }

    public func fields(_ c: ExportContext) -> [ExportField] {
        var out: [ExportField] = [
            ExportField("id", String(id)),
            ExportField("ledger", .integer(Int(ledger))),
        ]
        if let name = c.ledgerName(ledger) { out.append(ExportField("ledger_name", name)) }
        out.append(ExportField("code", .integer(Int(code))))
        if let label = c.codeLabel(code, transfer: false) { out.append(ExportField("code_label", label)) }
        out += [
            ExportField("flags", .integer(Int(flags.rawValue))),
            ExportField("flag_names", .list(flags.names)),
        ]
        out += amount("debits_pending", debitsPending, c)
        out += amount("debits_posted", debitsPosted, c)
        out += amount("credits_pending", creditsPending, c)
        out += amount("credits_posted", creditsPosted, c)
        out += signed("net_posted", netPosted, c)
        out += [
            ExportField("user_data_128", String(userData128)),
            ExportField("user_data_64", String(userData64)),
            ExportField("user_data_32", .integer(Int(userData32))),
            ExportField("timestamp", String(timestamp)),
            ExportField("timestamp_iso", TBFormat.iso8601(timestamp)),
        ]
        return out
    }

    private func amount(_ name: String, _ v: UInt128, _ c: ExportContext) -> [ExportField] {
        var out = [ExportField(name, String(v))]
        if let text = c.formatted(v, ledger: ledger) { out.append(ExportField("\(name)_formatted", text)) }
        return out
    }

    private func signed(_ name: String, _ v: SignedAmount, _ c: ExportContext) -> [ExportField] {
        var out = [ExportField(name, v.exactString)]
        if let text = c.formatted(v, ledger: ledger) { out.append(ExportField("\(name)_formatted", text)) }
        return out
    }
}

extension Transfer: ExportRow {
    public static var kind: String { "transfers" }

    public static var zero: Transfer {
        Transfer(
            id: 0, debitAccountID: 0, creditAccountID: 0, amount: 0, pendingID: 0,
            userData128: 0, userData64: 0, userData32: 0, timeout: 0, ledger: 0, code: 0,
            flags: TransferFlags(rawValue: 0), timestamp: 0)
    }

    public func fields(_ c: ExportContext) -> [ExportField] {
        var out: [ExportField] = [
            ExportField("id", String(id)),
            ExportField("debit_account_id", String(debitAccountID)),
            ExportField("credit_account_id", String(creditAccountID)),
            ExportField("amount", String(amount)),
        ]
        if let text = c.formatted(amount, ledger: ledger) {
            out.append(ExportField("amount_formatted", text))
        }
        out.append(ExportField("ledger", .integer(Int(ledger))))
        if let name = c.ledgerName(ledger) { out.append(ExportField("ledger_name", name)) }
        out.append(ExportField("code", .integer(Int(code))))
        if let label = c.codeLabel(code, transfer: true) { out.append(ExportField("code_label", label)) }
        out += [
            ExportField("flags", .integer(Int(flags.rawValue))),
            ExportField("flag_names", .list(flags.names)),
            ExportField("pending_id", String(pendingID)),
            ExportField("timeout", .integer(Int(timeout))),
            ExportField("user_data_128", String(userData128)),
            ExportField("user_data_64", String(userData64)),
            ExportField("user_data_32", .integer(Int(userData32))),
            ExportField("timestamp", String(timestamp)),
            ExportField("timestamp_iso", TBFormat.iso8601(timestamp)),
        ]
        return out
    }
}

extension Balance: ExportRow {
    public static var kind: String { "balances" }

    public static var zero: Balance {
        Balance(
            debitsPending: 0, debitsPosted: 0, creditsPending: 0, creditsPosted: 0, timestamp: 0)
    }

    /// A balance carries no ledger of its own, so the context supplies the owning account's.
    public func fields(_ c: ExportContext) -> [ExportField] {
        var out: [ExportField] = [ExportField("ledger", .integer(Int(c.ledger)))]
        out += amount("debits_pending", debitsPending, c)
        out += amount("debits_posted", debitsPosted, c)
        out += amount("credits_pending", creditsPending, c)
        out += amount("credits_posted", creditsPosted, c)
        var net = [ExportField("net_posted", netPosted.exactString)]
        if let text = c.formatted(netPosted, ledger: c.ledger) {
            net.append(ExportField("net_posted_formatted", text))
        }
        out += net
        out += [
            ExportField("timestamp", String(timestamp)),
            ExportField("timestamp_iso", TBFormat.iso8601(timestamp)),
        ]
        return out
    }

    private func amount(_ name: String, _ v: UInt128, _ c: ExportContext) -> [ExportField] {
        var out = [ExportField(name, String(v))]
        if let text = c.formatted(v, ledger: c.ledger) { out.append(ExportField("\(name)_formatted", text)) }
        return out
    }
}

extension SignedAmount {
    /// The exact value with an ASCII minus, unlike the display form which uses U+2212.
    public var exactString: String {
        isNegative && magnitude != 0 ? "-\(magnitude)" : String(magnitude)
    }
}
