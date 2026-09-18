import Foundation
import Testing
@testable import TBKit

@Suite("Export encoding")
struct ExportTests {
    private let usd = ClusterMetadata(ledgers: ["840": LedgerFormat(name: "USD", symbol: "$", exponent: 2)])

    private func transfer(
        id: UInt128 = 100_539, amount: UInt128 = 71_001, ledger: UInt32 = 840, code: UInt16 = 20,
        flags: TransferFlags = [.pending], timestamp: UInt64 = 1_758_033_192_527_027_008
    ) -> Transfer {
        Transfer(
            id: id, debitAccountID: 1016, creditAccountID: 1017, amount: amount, pendingID: 0,
            userData128: 9020, userData64: 6, userData32: 3, timeout: 0, ledger: ledger, code: code,
            flags: flags, timestamp: timestamp)
    }

    private func account(ledger: UInt32 = 840, code: UInt16 = 2) -> Account {
        Account(
            id: 1017, debitsPending: 0, debitsPosted: 968_201, creditsPending: 71_001,
            creditsPosted: 938_316, userData128: 503, userData64: 3, userData32: 2, ledger: ledger,
            code: code, flags: [.history], timestamp: 1_758_033_191_192_448_017)
    }

    private func csv(_ text: String) -> [[String]] {
        text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.components(separatedBy: ",") }
    }

    // MARK: exactness

    @Test func amountsAndIDsStayExact() {
        let text = exportText([transfer(id: .max, amount: .max)], format: .csv, context: ExportContext())
        let rows = csv(text)
        let id = rows[0].firstIndex(of: "id")!
        let amount = rows[0].firstIndex(of: "amount")!
        #expect(rows[1][id] == String(UInt128.max))
        #expect(rows[1][amount] == String(UInt128.max))
        #expect(String(UInt128.max).count == 39)
    }

    @Test func jsonKeepsIDsAsStringsAndSmallNumbersAsNumbers() throws {
        let text = exportText([transfer()], format: .json, context: ExportContext())
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        let row = (parsed["rows"] as! [[String: Any]])[0]

        #expect(row["id"] is String, "a u128 cannot survive as a JSON number")
        #expect(row["amount"] is String)
        #expect(row["timestamp"] is String)
        #expect(row["ledger"] is Int)
        #expect(row["code"] is Int)
        #expect(row["id"] as? String == "100539")
        #expect(row["flag_names"] as? [String] == ["pending"])
    }

    @Test func jsonEnvelopeNamesTheCluster() throws {
        let provenance = ExportProvenance(
            kind: "transfers", clusterID: 7, query: "query_transfers ledger=840",
            link: "tb-explorer://transfers?cluster=7")
        let text = exportText(
            [transfer()], format: .json, context: ExportContext(), provenance: provenance)
        let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]

        #expect(parsed["kind"] as? String == "transfers")
        #expect(parsed["cluster_id"] as? String == "7")
        #expect(parsed["query"] as? String == "query_transfers ledger=840")
        #expect(parsed["source"] as? String == "tb-explorer://transfers?cluster=7")
        #expect((parsed["columns"] as? [String])?.contains("amount") == true)
    }

    @Test func jsonStaysValidForOneRowManyRowsAndNone() throws {
        for count in [0, 1, 3] {
            let rows = Array(repeating: transfer(), count: count)
            let text = exportText(rows, format: .json, context: ExportContext())
            let parsed = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
            #expect((parsed["rows"] as! [Any]).count == count)
        }
    }

    // MARK: formatted columns are opt-in

    @Test func formattedColumnsAreAbsentUnlessAsked() {
        let rows = csv(exportText([transfer()], format: .csv, context: ExportContext(metadata: usd)))
        #expect(rows[0].contains("amount"))
        #expect(!rows[0].contains("amount_formatted"))
        #expect(!rows[0].contains("ledger_name"))
        #expect(rows[0].count == rows[1].count, "header and row must agree")
    }

    @Test func formattedColumnsAppearWhenAsked() {
        let context = ExportContext(metadata: usd, includeFormatted: true, grouping: ",", decimal: ".")
        let rows = csv(exportText([transfer()], format: .csv, context: context))
        let formatted = rows[0].firstIndex(of: "amount_formatted")!
        let name = rows[0].firstIndex(of: "ledger_name")!

        #expect(rows[1][formatted] == "710.01\u{00A0}$")
        #expect(rows[1][name] == "USD")
        #expect(rows[0].count == rows[1].count)
    }

    /// One export can span ledgers, so the columns cannot depend on the row: a ledger with no
    /// format gets the column with nothing in it, never a shorter row.
    @Test func aLedgerWithNoFormatGetsEmptyFormattedColumns() {
        let context = ExportContext(metadata: usd, includeFormatted: true)
        // 700 is unassigned in ISO 4217 and has no override.
        let rows = csv(exportText([transfer(ledger: 700)], format: .csv, context: context))
        let formatted = rows[0].firstIndex(of: "amount_formatted")!
        let name = rows[0].firstIndex(of: "ledger_name")!
        #expect(rows[1][formatted] == "")
        #expect(rows[1][name] == "")
    }

    @Test func mixedLedgersKeepOneSetOfColumns() {
        let context = ExportContext(metadata: usd, includeFormatted: true, decimal: ".")
        let text = exportText(
            [transfer(ledger: 700), transfer(ledger: 840)], format: .csv, context: context)
        let rows = csv(text)
        #expect(rows[0].count == rows[1].count)
        #expect(rows[1].count == rows[2].count, "a ragged file puts values under the wrong heading")
        let formatted = rows[0].firstIndex(of: "amount_formatted")!
        #expect(rows[1][formatted] == "")
        #expect(rows[2][formatted] == "710.01\u{00A0}$")
    }

    @Test func codeLabelsComeFromMetadata() {
        var metadata = usd
        metadata.transferCodes["20"] = "settlement"
        let context = ExportContext(metadata: metadata, includeFormatted: true)
        let rows = csv(exportText([transfer()], format: .csv, context: context))
        let label = rows[0].firstIndex(of: "code_label")!
        #expect(rows[1][label] == "settlement")
    }

    @Test func separatorsDoNotFollowTheMachinesLocale() {
        let context = ExportContext(metadata: usd, includeFormatted: true, grouping: " ", decimal: ",")
        let text = exportText([transfer(amount: 123_456_789)], format: .csv, context: context)
        #expect(text.contains("1 234 567,89"))
    }

    // MARK: accounts and balances

    @Test func accountsCarryTheirNetPosted() {
        let rows = csv(exportText([account()], format: .csv, context: ExportContext()))
        let net = rows[0].firstIndex(of: "net_posted")!
        // credits_posted 938316 − debits_posted 968201
        #expect(rows[1][net] == "-29885")
    }

    @Test func balancesTakeTheLedgerFromTheirAccount() {
        let balance = Balance(
            debitsPending: 0, debitsPosted: 968_201, creditsPending: 0, creditsPosted: 938_316,
            timestamp: 1_758_033_192_527_027_008)
        let context = ExportContext(metadata: usd, includeFormatted: true, ledger: 840, decimal: ".")
        let rows = csv(exportText([balance], format: .csv, context: context))
        let ledger = rows[0].firstIndex(of: "ledger")!
        #expect(rows[1][ledger] == "840")
        #expect(rows[0].contains("debits_posted_formatted"))
    }

    // MARK: CSV shape

    @Test func quotesOnlyWhatNeedsIt() {
        #expect(CSVExportWriter.escape("plain") == "plain")
        #expect(CSVExportWriter.escape("") == "")
        #expect(CSVExportWriter.escape("a,b") == "\"a,b\"")
        #expect(CSVExportWriter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVExportWriter.escape("two\nlines") == "\"two\nlines\"")
    }

    @Test func aFormattedAmountWithACommaIsQuoted() {
        let context = ExportContext(metadata: usd, includeFormatted: true, grouping: ".", decimal: ",")
        let text = exportText([transfer()], format: .csv, context: context)
        #expect(text.contains("\"710,01\u{00A0}$\""))
    }

    @Test func flagsAreBothRawAndNamed() {
        let rows = csv(
            exportText(
                [transfer(flags: [.pending, .linked])], format: .csv, context: ExportContext()))
        let raw = rows[0].firstIndex(of: "flags")!
        let names = rows[0].firstIndex(of: "flag_names")!
        #expect(rows[1][raw] == "3")
        #expect(rows[1][names] == "linked pending")
    }

    @Test func anEmptyExportStillNamesItsColumns() {
        let rows = csv(exportText([Transfer](), format: .csv, context: ExportContext()))
        #expect(rows.count == 1)
        #expect(rows[0].first == "id")
    }

    // MARK: timestamps

    @Test func timestampsCarryBothFormsInUTC() {
        let rows = csv(exportText([transfer()], format: .csv, context: ExportContext()))
        let ns = rows[0].firstIndex(of: "timestamp")!
        let iso = rows[0].firstIndex(of: "timestamp_iso")!
        #expect(rows[1][ns] == "1758033192527027008")
        #expect(rows[1][iso] == "2025-09-16T14:33:12.527027008Z")
    }

    @Test func aZeroTimestampIsEmptyRatherThan1970() {
        #expect(TBFormat.iso8601(0).isEmpty)
    }
}
