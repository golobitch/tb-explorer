import Foundation
import TBKit

/// How amounts, ledgers and codes are rendered on screen.
///
/// A plain value type, passed explicitly into tables and rows. `Table` cells are hosted and
/// recycled separately, so they must not read `@Observable` state from the environment
/// (see the note on `IDText` in `Components.swift`).
struct AmountStyle: Equatable, Sendable {
    var metadata: ClusterMetadata
    /// Format amounts using the ledger id's ISO 4217 currency when no override exists.
    var useCurrencyFormat: Bool

    /// Exact integers, no labels: what the app showed before this setting existed.
    static let raw = AmountStyle(metadata: ClusterMetadata(), useCurrencyFormat: false)

    func format(ledger: UInt32) -> LedgerFormat? {
        metadata.format(forLedger: ledger, useCurrencies: useCurrencyFormat)
    }

    func text(_ v: UInt128, ledger: UInt32) -> String {
        TBFormat.amount(v, format: format(ledger: ledger))
    }

    func text(_ v: SignedAmount, ledger: UInt32) -> String {
        TBFormat.amount(v, format: format(ledger: ledger))
    }

    /// The other form of the same amount, for a tooltip: the exact integer when the amount is
    /// formatted, and nil when it is already raw.
    func alternate(_ v: UInt128, ledger: UInt32) -> String? {
        format(ledger: ledger) == nil ? nil : "Exact: \(v)"
    }

    func alternate(_ v: SignedAmount, ledger: UInt32) -> String? {
        guard format(ledger: ledger) != nil else { return nil }
        return "Exact: \(v.isNegative && v.magnitude != 0 ? "−" : "")\(v.magnitude)"
    }

    /// `840 · USD`, or just `840` when the ledger has no format.
    func ledgerLabel(_ ledger: UInt32) -> String {
        guard let name = format(ledger: ledger)?.name else { return String(ledger) }
        return "\(ledger) · \(name)"
    }

    func transferCodeLabel(_ code: UInt16) -> String {
        label(code, metadata.transferCode(code))
    }

    func accountCodeLabel(_ code: UInt16) -> String {
        label(code, metadata.accountCode(code))
    }

    private func label(_ code: UInt16, _ name: String?) -> String {
        guard let name, !name.isEmpty else { return String(code) }
        return "\(code) · \(name)"
    }
}
