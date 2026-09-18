import Foundation
import Testing
@testable import TBKit

@Suite("UInt128 and formatting")
struct FormatTests {
    @Test("parses decimal, hex and separators beyond 2^64", arguments: [
        ("0", UInt128(0)),
        ("1_000", UInt128(1000)),
        ("18446744073709551616", UInt128(1) << 64),
        ("0xff", UInt128(255)),
        ("0x10000000000000000", UInt128(1) << 64),
        ("340282366920938463463374607431768211455", UInt128.max),
        (" 12, 345 ", UInt128(12345)),
    ])
    func parse(input: String, expected: UInt128) {
        #expect(UInt128(tbString: input) == expected)
    }

    @Test("rejects invalid input", arguments: [
        "", "-1", "1.5", "abc", "0x", "340282366920938463463374607431768211456", "٣",
    ])
    func rejects(input: String) {
        #expect(UInt128(tbString: input) == nil)
    }

    @Test func groupsDigits() {
        #expect(TBFormat.amount(UInt128(1_234_567), separator: ",") == "1,234,567")
        #expect(TBFormat.amount(UInt128(12), separator: ",") == "12")
        #expect(TBFormat.amount(UInt128.max, separator: "") == "340282366920938463463374607431768211455")
    }

    @Test func signedAmounts() {
        let neg = SignedAmount(credits: 5, debits: 1005)
        #expect(neg.isNegative && neg.magnitude == 1000)
        #expect(TBFormat.amount(neg, separator: ",") == "−1,000")
        #expect(TBFormat.amount(SignedAmount(credits: 3, debits: 3), separator: ",") == "0")
        // The full u128 span, which Int128 could not hold.
        let wide = SignedAmount(credits: 0, debits: .max)
        #expect(wide.magnitude == .max && wide.isNegative)
        #expect(SignedAmount(credits: 0, debits: 2) < SignedAmount(credits: 0, debits: 1))
    }

    @Test func timestamps() {
        let ns: UInt64 = 1_757_900_000_123_456_789
        #expect(TBFormat.timestamp(ns, timeZone: TimeZone(identifier: "UTC")!) == "2025-09-15 01:33:20.123456789")
        #expect(TBFormat.timestamp(0) == "—")
        #expect(TBFormat.nanos(TBFormat.date(ns)) == 1_757_900_000_123_000_000)
    }

    @Test func flagNames() {
        #expect(AccountFlags.history.names == ["history"])
        #expect(TransferFlags([.linked, .pending, .voidPendingTransfer]).names == ["linked", "pending", "void_pending_transfer"])
        #expect(AccountFlags(rawValue: 1 << 10).names == ["unknown_bit_10"])
        #expect(TransferFlags().names.isEmpty)
    }

    @Test func cursor() {
        #expect(Cursor.next(after: 10, reversed: false) == (11, nil))
        #expect(Cursor.next(after: 10, reversed: true) == (nil, 9))
    }

    @Test func vendoredVersionMatches() throws {
        // ui/Tests/TBKitTests/FormatTests.swift → the repo root, where Vendor is shared with cli.
        let versionFile = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Vendor/tigerbeetle/VERSION")
        let vendored = try String(contentsOf: versionFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(vendored == TBClient.clientVersion)
    }
}
