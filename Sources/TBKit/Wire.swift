import Foundation

/// Explicit little-endian encoding of TigerBeetle's extern structs.
///
/// Swift cannot import the C structs' `__uint128_t` fields, so events and results
/// are read and written at the offsets defined by `tb_client.h`. `WireLayoutTests`
/// pins these offsets and sizes.
enum Wire {
    static let accountSize = 128
    static let transferSize = 128
    static let balanceSize = 128
    static let accountFilterSize = 128
    static let queryFilterSize = 64
    static let idSize = 16

    enum AccountOffset {
        static let id = 0, debitsPending = 16, debitsPosted = 32, creditsPending = 48, creditsPosted = 64
        static let userData128 = 80, userData64 = 96, userData32 = 104, reserved = 108
        static let ledger = 112, code = 116, flags = 118, timestamp = 120
    }

    enum TransferOffset {
        static let id = 0, debitAccountID = 16, creditAccountID = 32, amount = 48, pendingID = 64
        static let userData128 = 80, userData64 = 96, userData32 = 104, timeout = 108
        static let ledger = 112, code = 116, flags = 118, timestamp = 120
    }

    enum BalanceOffset {
        static let debitsPending = 0, debitsPosted = 16, creditsPending = 32, creditsPosted = 48, timestamp = 64
    }

    enum AccountFilterOffset {
        static let accountID = 0, userData128 = 16, userData64 = 32, userData32 = 40, code = 44
        static let timestampMin = 104, timestampMax = 112, limit = 120, flags = 124
    }

    enum QueryFilterOffset {
        static let userData128 = 0, userData64 = 16, userData32 = 24, ledger = 28, code = 32
        static let timestampMin = 40, timestampMax = 48, limit = 56, flags = 60
    }

    // MARK: Decoding

    static func decode<T>(_ bytes: [UInt8], size: Int, _ one: (UnsafeRawBufferPointer, Int) -> T) -> [T] {
        precondition(bytes.count % size == 0, "misaligned TigerBeetle reply: \(bytes.count) bytes")
        return bytes.withUnsafeBytes { raw in
            stride(from: 0, to: raw.count, by: size).map { one(raw, $0) }
        }
    }

    static func accounts(_ bytes: [UInt8]) -> [Account] {
        decode(bytes, size: accountSize) { r, o in
            typealias O = AccountOffset
            return Account(
                id: r.loadUnaligned(fromByteOffset: o + O.id, as: UInt128.self).littleEndian,
                debitsPending: r.loadUnaligned(fromByteOffset: o + O.debitsPending, as: UInt128.self).littleEndian,
                debitsPosted: r.loadUnaligned(fromByteOffset: o + O.debitsPosted, as: UInt128.self).littleEndian,
                creditsPending: r.loadUnaligned(fromByteOffset: o + O.creditsPending, as: UInt128.self).littleEndian,
                creditsPosted: r.loadUnaligned(fromByteOffset: o + O.creditsPosted, as: UInt128.self).littleEndian,
                userData128: r.loadUnaligned(fromByteOffset: o + O.userData128, as: UInt128.self).littleEndian,
                userData64: r.loadUnaligned(fromByteOffset: o + O.userData64, as: UInt64.self).littleEndian,
                userData32: r.loadUnaligned(fromByteOffset: o + O.userData32, as: UInt32.self).littleEndian,
                ledger: r.loadUnaligned(fromByteOffset: o + O.ledger, as: UInt32.self).littleEndian,
                code: r.loadUnaligned(fromByteOffset: o + O.code, as: UInt16.self).littleEndian,
                flags: AccountFlags(rawValue: r.loadUnaligned(fromByteOffset: o + O.flags, as: UInt16.self).littleEndian),
                timestamp: r.loadUnaligned(fromByteOffset: o + O.timestamp, as: UInt64.self).littleEndian
            )
        }
    }

    static func transfers(_ bytes: [UInt8]) -> [Transfer] {
        decode(bytes, size: transferSize) { r, o in
            typealias O = TransferOffset
            return Transfer(
                id: r.loadUnaligned(fromByteOffset: o + O.id, as: UInt128.self).littleEndian,
                debitAccountID: r.loadUnaligned(fromByteOffset: o + O.debitAccountID, as: UInt128.self).littleEndian,
                creditAccountID: r.loadUnaligned(fromByteOffset: o + O.creditAccountID, as: UInt128.self).littleEndian,
                amount: r.loadUnaligned(fromByteOffset: o + O.amount, as: UInt128.self).littleEndian,
                pendingID: r.loadUnaligned(fromByteOffset: o + O.pendingID, as: UInt128.self).littleEndian,
                userData128: r.loadUnaligned(fromByteOffset: o + O.userData128, as: UInt128.self).littleEndian,
                userData64: r.loadUnaligned(fromByteOffset: o + O.userData64, as: UInt64.self).littleEndian,
                userData32: r.loadUnaligned(fromByteOffset: o + O.userData32, as: UInt32.self).littleEndian,
                timeout: r.loadUnaligned(fromByteOffset: o + O.timeout, as: UInt32.self).littleEndian,
                ledger: r.loadUnaligned(fromByteOffset: o + O.ledger, as: UInt32.self).littleEndian,
                code: r.loadUnaligned(fromByteOffset: o + O.code, as: UInt16.self).littleEndian,
                flags: TransferFlags(rawValue: r.loadUnaligned(fromByteOffset: o + O.flags, as: UInt16.self).littleEndian),
                timestamp: r.loadUnaligned(fromByteOffset: o + O.timestamp, as: UInt64.self).littleEndian
            )
        }
    }

    static func balances(_ bytes: [UInt8]) -> [Balance] {
        decode(bytes, size: balanceSize) { r, o in
            typealias O = BalanceOffset
            return Balance(
                debitsPending: r.loadUnaligned(fromByteOffset: o + O.debitsPending, as: UInt128.self).littleEndian,
                debitsPosted: r.loadUnaligned(fromByteOffset: o + O.debitsPosted, as: UInt128.self).littleEndian,
                creditsPending: r.loadUnaligned(fromByteOffset: o + O.creditsPending, as: UInt128.self).littleEndian,
                creditsPosted: r.loadUnaligned(fromByteOffset: o + O.creditsPosted, as: UInt128.self).littleEndian,
                timestamp: r.loadUnaligned(fromByteOffset: o + O.timestamp, as: UInt64.self).littleEndian
            )
        }
    }

    // MARK: Encoding

    struct Writer {
        var bytes: [UInt8]
        init(size: Int) { bytes = [UInt8](repeating: 0, count: size) }

        mutating func put<T: FixedWidthInteger>(_ v: T, at offset: Int) {
            withUnsafeBytes(of: v.littleEndian) { src in
                bytes.replaceSubrange(offset..<offset + src.count, with: src)
            }
        }
    }

    static func ids(_ ids: [UInt128]) -> [UInt8] {
        var w = Writer(size: ids.count * idSize)
        for (i, id) in ids.enumerated() { w.put(id, at: i * idSize) }
        return w.bytes
    }

    static func encode(_ f: QueryFilter) -> [UInt8] {
        typealias O = QueryFilterOffset
        var w = Writer(size: queryFilterSize)
        w.put(f.userData128, at: O.userData128)
        w.put(f.userData64, at: O.userData64)
        w.put(f.userData32, at: O.userData32)
        w.put(f.ledger, at: O.ledger)
        w.put(f.code, at: O.code)
        w.put(f.timestampMin, at: O.timestampMin)
        w.put(f.timestampMax, at: O.timestampMax)
        w.put(clampLimit(f.limit), at: O.limit)
        w.put(UInt32(f.reversed ? 1 : 0), at: O.flags)
        return w.bytes
    }

    static func encode(_ f: AccountFilter, accountID: UInt128) -> [UInt8] {
        typealias O = AccountFilterOffset
        var w = Writer(size: accountFilterSize)
        // TigerBeetle rejects a filter with neither side selected; treat it as both.
        let both = !f.debits && !f.credits
        var flags: UInt32 = 0
        if f.debits || both { flags |= 1 << 0 }
        if f.credits || both { flags |= 1 << 1 }
        if f.reversed { flags |= 1 << 2 }
        w.put(accountID, at: O.accountID)
        w.put(f.userData128, at: O.userData128)
        w.put(f.userData64, at: O.userData64)
        w.put(f.userData32, at: O.userData32)
        w.put(f.code, at: O.code)
        w.put(f.timestampMin, at: O.timestampMin)
        w.put(f.timestampMax, at: O.timestampMax)
        w.put(clampLimit(f.limit), at: O.limit)
        w.put(flags, at: O.flags)
        return w.bytes
    }
}
