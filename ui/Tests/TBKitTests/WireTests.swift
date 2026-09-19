import CTigerBeetle
import Testing
@testable import TBKit

@Suite("Wire layout")
struct WireTests {
    @Test("struct sizes match tb_client.h")
    func sizes() {
        #expect(MemoryLayout<tb_account_t>.size == Wire.accountSize)
        #expect(MemoryLayout<tb_transfer_t>.size == Wire.transferSize)
        #expect(MemoryLayout<tb_account_balance_t>.size == Wire.balanceSize)
        #expect(MemoryLayout<tb_account_filter_t>.size == Wire.accountFilterSize)
        #expect(MemoryLayout<tb_query_filter_t>.size == Wire.queryFilterSize)
    }

    @Test("C-visible offsets agree with Wire")
    func cOffsets() {
        // Fields without u128 import into Swift, so their offsets can be checked directly.
        #expect(MemoryLayout<tb_account_t>.offset(of: \.user_data_64) == Wire.AccountOffset.userData64)
        #expect(MemoryLayout<tb_account_t>.offset(of: \.ledger) == Wire.AccountOffset.ledger)
        #expect(MemoryLayout<tb_account_t>.offset(of: \.flags) == Wire.AccountOffset.flags)
        #expect(MemoryLayout<tb_account_t>.offset(of: \.timestamp) == Wire.AccountOffset.timestamp)
        #expect(MemoryLayout<tb_transfer_t>.offset(of: \.timeout) == Wire.TransferOffset.timeout)
        #expect(MemoryLayout<tb_transfer_t>.offset(of: \.timestamp) == Wire.TransferOffset.timestamp)
        #expect(MemoryLayout<tb_account_balance_t>.offset(of: \.timestamp) == Wire.BalanceOffset.timestamp)
        #expect(MemoryLayout<tb_account_filter_t>.offset(of: \.code) == Wire.AccountFilterOffset.code)
        #expect(MemoryLayout<tb_account_filter_t>.offset(of: \.timestamp_min) == Wire.AccountFilterOffset.timestampMin)
        #expect(MemoryLayout<tb_account_filter_t>.offset(of: \.flags) == Wire.AccountFilterOffset.flags)
        #expect(MemoryLayout<tb_query_filter_t>.offset(of: \.ledger) == Wire.QueryFilterOffset.ledger)
        #expect(MemoryLayout<tb_query_filter_t>.offset(of: \.limit) == Wire.QueryFilterOffset.limit)
        #expect(MemoryLayout<tb_query_filter_t>.offset(of: \.flags) == Wire.QueryFilterOffset.flags)
    }

    @Test("query filter encodes into a C struct")
    func queryFilterRoundTrip() {
        let f = QueryFilter(
            ledger: 700, code: 20, userData128: .max, userData64: 42, userData32: 7,
            timestampMin: 11, timestampMax: 99, limit: 50, reversed: true)
        let bytes = Wire.encode(f)
        let c = bytes.withUnsafeBytes { $0.loadUnaligned(as: tb_query_filter_t.self) }
        #expect(c.ledger == 700)
        #expect(c.code == 20)
        #expect(c.user_data_64 == 42)
        #expect(c.user_data_32 == 7)
        #expect(c.timestamp_min == 11)
        #expect(c.timestamp_max == 99)
        #expect(c.limit == 50)
        #expect(c.flags == TB_QUERY_FILTER_REVERSED.rawValue)
        #expect(bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt128.self) } == .max)
    }

    @Test("account filter defaults to both sides and clamps limit")
    func accountFilter() {
        let bytes = Wire.encode(AccountFilter(debits: false, credits: false, limit: 1_000_000), accountID: 1001)
        let c = bytes.withUnsafeBytes { $0.loadUnaligned(as: tb_account_filter_t.self) }
        #expect(c.flags == TB_ACCOUNT_FILTER_DEBITS.rawValue | TB_ACCOUNT_FILTER_CREDITS.rawValue)
        #expect(c.limit == tbMaxLimit)
        #expect(bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt128.self) } == 1001)
    }

    @Test("transfer decodes every field at the right offset")
    func transferDecode() {
        var w = Wire.Writer(size: Wire.transferSize)
        typealias O = Wire.TransferOffset
        w.put(UInt128.max - 1, at: O.id)
        w.put(UInt128(1001), at: O.debitAccountID)
        w.put(UInt128(1002), at: O.creditAccountID)
        w.put(UInt128(1) << 100, at: O.amount)
        w.put(UInt128(5), at: O.pendingID)
        w.put(UInt128(6), at: O.userData128)
        w.put(UInt64(7), at: O.userData64)
        w.put(UInt32(8), at: O.userData32)
        w.put(UInt32(3600), at: O.timeout)
        w.put(UInt32(840), at: O.ledger)
        w.put(UInt16(10), at: O.code)
        w.put(UInt16(0b1010), at: O.flags)
        w.put(UInt64.max, at: O.timestamp)
        let t = Wire.transfers(w.bytes + w.bytes)
        #expect(t.count == 2)
        #expect(t[1].id == UInt128.max - 1)
        #expect(t[1].debitAccountID == 1001)
        #expect(t[1].creditAccountID == 1002)
        #expect(t[1].amount == UInt128(1) << 100)
        #expect(t[1].pendingID == 5)
        #expect(t[1].userData128 == 6)
        #expect(t[1].userData64 == 7)
        #expect(t[1].userData32 == 8)
        #expect(t[1].timeout == 3600)
        #expect(t[1].ledger == 840)
        #expect(t[1].code == 10)
        #expect(t[1].flags == [.pending, .voidPendingTransfer])
        #expect(t[1].timestamp == .max)
    }

    @Test("lookup ids are 16 little-endian bytes each")
    func ids() {
        let b = Wire.ids([1, .max])
        #expect(b.count == 32)
        #expect(b[0] == 1 && b[1...15].allSatisfy { $0 == 0 })
        #expect(b[16...].allSatisfy { $0 == 0xFF })
    }
}
