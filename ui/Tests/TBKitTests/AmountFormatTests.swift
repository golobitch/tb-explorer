import Foundation
import Testing
@testable import TBKit

@Suite("Amount scaling")
struct AmountFormatTests {
    /// Fixed separators keep these assertions independent of the machine's locale.
    private func text(_ v: UInt128, _ format: LedgerFormat?) -> String {
        TBFormat.amount(v, format: format, grouping: ",", decimal: ".")
    }

    @Test func exponentZeroIsGroupedOnly() {
        #expect(text(123_456, LedgerFormat(name: "JPY", exponent: 0)) == "123,456\u{00A0}JPY")
        #expect(text(123_456, nil) == "123,456")
    }

    @Test func insertsTheDecimalPoint() {
        let usd = LedgerFormat(name: "USD", symbol: "$", exponent: 2)
        #expect(text(123_456, usd) == "1,234.56\u{00A0}$")
        #expect(text(1_234_567, usd) == "12,345.67\u{00A0}$")
        #expect(text(100, usd) == "1.00\u{00A0}$")
    }

    @Test func padsValuesSmallerThanOneUnit() {
        let usd = LedgerFormat(name: "USD", exponent: 2)
        #expect(text(5, usd) == "0.05\u{00A0}USD")
        #expect(text(50, usd) == "0.50\u{00A0}USD")
        #expect(text(0, usd) == "0.00\u{00A0}USD")
    }

    @Test func threeAndFourDecimalCurrencies() {
        #expect(text(1234, LedgerFormat(name: "BHD", exponent: 3)) == "1.234\u{00A0}BHD")
        #expect(text(12, LedgerFormat(name: "CLF", exponent: 4)) == "0.0012\u{00A0}CLF")
    }

    @Test func keepsFullPrecisionAtTheExtremes() {
        // 39 digits: one before the point, 38 after. Nothing may be rounded away.
        let format = LedgerFormat(exponent: 38)
        #expect(TBFormat.amount(UInt128.max, format: format, grouping: ",", decimal: ".")
            == "3.40282366920938463463374607431768211455")
        let e2 = LedgerFormat(exponent: 2)
        #expect(TBFormat.amount(UInt128.max, format: e2, grouping: "", decimal: ".")
            == "3402823669209384634633746074317682114.55")
    }

    @Test func groupsOnlyTheIntegerPart() {
        // Separators swapped, as in de/sl locales.
        #expect(TBFormat.amount(1_234_567, format: LedgerFormat(exponent: 2), grouping: ".", decimal: ",")
            == "12.345,67")
    }

    @Test func signedAmountsKeepTheSignOutside() {
        let usd = LedgerFormat(name: "USD", symbol: "$", exponent: 2)
        let negative = SignedAmount(credits: 0, debits: 123_456)
        #expect(TBFormat.amount(negative, format: usd, grouping: ",", decimal: ".") == "−1,234.56\u{00A0}$")
        let zero = SignedAmount(credits: 7, debits: 7)
        #expect(TBFormat.amount(zero, format: usd, grouping: ",", decimal: ".") == "0.00\u{00A0}$")
    }

    @Test func exponentIsClamped() {
        #expect(LedgerFormat(exponent: 200).exponent == LedgerFormat.maxExponent)
        #expect(LedgerFormat(name: "", symbol: "", exponent: 2).unit == nil)
    }
}

@Suite("ISO 4217 ledgers")
struct ISO4217Tests {
    @Test("numeric codes map to currencies", arguments: [
        (UInt32(840), "USD", UInt8(2)),
        (UInt32(978), "EUR", UInt8(2)),
        (UInt32(392), "JPY", UInt8(0)),
        (UInt32(48), "BHD", UInt8(3)),
        (UInt32(990), "CLF", UInt8(4)),
    ])
    func lookup(ledger: UInt32, alpha: String, exponent: UInt8) throws {
        let currency = try #require(ISO4217.currency(forLedger: ledger))
        #expect(currency.alpha == alpha)
        #expect(currency.exponent == exponent)
    }

    @Test func unassignedLedgersDoNotMatch() {
        // A ledger id is just a u32; ids outside the active list must stay raw.
        #expect(ISO4217.currency(forLedger: 0) == nil)
        #expect(ISO4217.currency(forLedger: 700) == nil)
        #expect(ISO4217.currency(forLedger: 4_294_967_295) == nil)
    }

    @Test func listIsSortedAndUnique() {
        let all = ISO4217.all
        #expect(all.count > 150)
        #expect(Set(all.map(\.numeric)).count == all.count)
        #expect(all.map(\.alpha) == all.map(\.alpha).sorted())
    }
}

@Suite("Cluster metadata")
struct MetadataTests {
    @Test func overrideWinsOverCurrencyMatch() {
        var metadata = ClusterMetadata()
        metadata[ledger: 840] = LedgerFormat(name: "points", exponent: 0)
        #expect(metadata.format(forLedger: 840, useCurrencies: true)?.name == "points")
        #expect(metadata.format(forLedger: 978, useCurrencies: true)?.name == "EUR")
        #expect(metadata.format(forLedger: 978, useCurrencies: false) == nil)
        #expect(metadata.format(forLedger: 700, useCurrencies: true) == nil)
    }

    @Test func codeLabels() {
        let metadata = ClusterMetadata(transferCodes: ["10": "payment"], accountCodes: ["1": "customer"])
        #expect(metadata.transferCode(10) == "payment")
        #expect(metadata.transferCode(11) == nil)
        #expect(metadata.accountCode(1) == "customer")
        #expect(!metadata.isEmpty)
        #expect(ClusterMetadata().isEmpty)
    }

    @Test func roundTrips() throws {
        var metadata = ClusterMetadata(transferCodes: ["10": "payment"])
        metadata[ledger: 840] = LedgerFormat(name: "USD", symbol: "$", exponent: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(metadata)
        #expect(try JSONDecoder().decode(ClusterMetadata.self, from: data) == metadata)
        // Keys stay decimal strings so the file is hand-editable.
        #expect(String(decoding: data, as: UTF8.self).contains("\"840\""))
    }

    @Test("partial and unknown JSON still loads", arguments: [
        "{}",
        #"{"ledgers":{"840":{"exponent":2}}}"#,
        #"{"transferCodes":{"10":"payment"},"somethingNew":42}"#,
        #"{"ledgers":{},"transferCodes":{},"accountCodes":{}}"#,
    ])
    func lenientDecoding(json: String) throws {
        let metadata = try JSONDecoder().decode(ClusterMetadata.self, from: Data(json.utf8))
        // Whatever was present decodes; whatever was missing is empty rather than a failure.
        #expect(metadata.ledgers.count <= 1)
    }

    @Test func currencyInitialiser() {
        let usd = try! #require(ISO4217.currency(forLedger: 840))
        let format = LedgerFormat(usd)
        #expect(format.name == "USD" && format.symbol == "$" && format.exponent == 2)
        #expect(format.unit == "$")
    }
}
