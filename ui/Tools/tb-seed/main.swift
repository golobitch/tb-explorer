// tb-seed populates a development TigerBeetle cluster with deterministic accounts and
// transfers covering every shape the explorer renders. Ids are fixed, so re-running is
// idempotent ("exists" results change nothing).
//
// This is the only code in the repository that issues create_* operations.

import CTigerBeetle
import Foundation
import TBKit

// MARK: Arguments

var addresses = "127.0.0.1:3000"
var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--addresses": addresses = args.next() ?? addresses
    default:
        FileHandle.standardError.write(Data("usage: tb-seed [--addresses host:port,...]\n".utf8))
        exit(2)
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
let client = SeedClient(addresses: addresses)

// MARK: Encoding (offsets from tb_client.h)

struct Bytes {
    var b: [UInt8]
    init(_ size: Int) { b = [UInt8](repeating: 0, count: size) }
    mutating func put<T: FixedWidthInteger>(_ v: T, _ at: Int) {
        withUnsafeBytes(of: v.littleEndian) { b.replaceSubrange(at..<at + $0.count, with: $0) }
    }
}

struct SeedAccount { var id: UInt128; var ledger: UInt32; var code: UInt16; var ud128: UInt128; var ud64: UInt64; var ud32: UInt32; var history: Bool }

struct SeedTransfer {
    var id: UInt128, debit: UInt128, credit: UInt128, amount: UInt128, pendingID: UInt128 = 0
    var ud128: UInt128 = 0, ud64: UInt64 = 0, ud32: UInt32 = 0, timeout: UInt32 = 0
    var ledger: UInt32, code: UInt16, flags: UInt16 = 0
}

func encode(_ a: SeedAccount) -> [UInt8] {
    var w = Bytes(128)
    w.put(a.id, 0); w.put(a.ud128, 80); w.put(a.ud64, 96); w.put(a.ud32, 104)
    w.put(a.ledger, 112); w.put(a.code, 116); w.put(UInt16(a.history ? 1 << 3 : 0), 118)
    return w.b
}

func encode(_ t: SeedTransfer) -> [UInt8] {
    var w = Bytes(128)
    w.put(t.id, 0); w.put(t.debit, 16); w.put(t.credit, 32); w.put(t.amount, 48); w.put(t.pendingID, 64)
    w.put(t.ud128, 80); w.put(t.ud64, 96); w.put(t.ud32, 104); w.put(t.timeout, 108)
    w.put(t.ledger, 112); w.put(t.code, 116); w.put(t.flags, 118)
    return w.b
}

/// Results are dense: one 16-byte (timestamp, status, reserved) record per event.
func tally(_ reply: [UInt8], created: UInt32, exists: UInt32, label: (Int) -> String) -> (Int, Int, Int) {
    var c = 0, e = 0, f = 0
    reply.withUnsafeBytes { raw in
        for i in 0..<(raw.count / 16) {
            let status = raw.loadUnaligned(fromByteOffset: i * 16 + 8, as: UInt32.self)
            switch status {
            case created: c += 1
            case exists: e += 1
            default:
                f += 1
                print("  \(label(i)): status \(status)")
            }
        }
    }
    return (c, e, f)
}

// MARK: Deterministic data

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

let ledgerEUR: UInt32 = 700, ledgerUSD: UInt32 = 840
let codePayment: UInt16 = 10, codeRefund: UInt16 = 11, codeHold: UInt16 = 20, codeFee: UInt16 = 30
let flagLinked: UInt16 = 1 << 0, flagPending: UInt16 = 1 << 1, flagPost: UInt16 = 1 << 2, flagVoid: UInt16 = 1 << 3
let amountMax = UInt128.max

var rng = SplitMix64(state: 42)

var accounts: [SeedAccount] = []
@MainActor
func addAccounts(_ n: Int, _ ledger: UInt32, _ code: UInt16, history: Bool) {
    for _ in 0..<n {
        accounts.append(SeedAccount(
            id: UInt128(1_000 + accounts.count + 1), ledger: ledger, code: code,
            ud128: UInt128(500 + rng.int(5)), ud64: UInt64(rng.int(3) + 1), ud32: UInt32(rng.int(4) + 1),
            history: history))
    }
}
addAccounts(6, ledgerEUR, 1, history: true)
addAccounts(4, ledgerEUR, 2, history: false)
addAccounts(2, ledgerEUR, 3, history: true)
addAccounts(4, ledgerUSD, 1, history: false)
addAccounts(3, ledgerUSD, 2, history: true)
addAccounts(1, ledgerUSD, 3, history: false)
let byLedger = Dictionary(grouping: accounts, by: \.ledger)

var nextTransfer: UInt128 = 100_000
@MainActor
func nextID() -> UInt128 { nextTransfer += 1; return nextTransfer }

@MainActor
func base(_ code: UInt16) -> SeedTransfer {
    let ledger = rng.int(3) == 0 ? ledgerUSD : ledgerEUR
    let accs = byLedger[ledger]!
    let i = rng.int(accs.count)
    var j = rng.int(accs.count - 1)
    if j >= i { j += 1 }
    return SeedTransfer(
        id: nextID(), debit: accs[i].id, credit: accs[j].id, amount: UInt128(100 + rng.int(99_900)),
        ud128: UInt128(9_000 + rng.int(50)), ud64: UInt64(rng.int(10)), ud32: UInt32(rng.int(4) + 1),
        ledger: ledger, code: code)
}

@MainActor
func resolution(of p: SeedTransfer, flags: UInt16, amount: UInt128 = 0) -> SeedTransfer {
    SeedTransfer(id: nextID(), debit: p.debit, credit: p.credit, amount: amount, pendingID: p.id,
                 ledger: p.ledger, code: p.code, flags: flags)
}

var batches: [[SeedTransfer]] = []
var followups: [SeedTransfer] = []

for round in 0..<35 {
    batches.append((0..<10).map { _ in
        switch rng.int(10) {
        case 0: base(codeRefund)
        case 1: base(codeFee)
        default: base(codePayment)
        }
    })

    var pending: [SeedTransfer] = []
    if round < 20 { // 40 pending → post, every second one partial
        for i in 0..<2 {
            var p = base(codeHold)
            p.flags = flagPending
            p.timeout = 3600
            pending.append(p)
            followups.append(resolution(of: p, flags: flagPost, amount: i == 1 ? p.amount / 2 : amountMax))
        }
    } else if round < 30 { // 25 pending → void
        for _ in 0..<(round % 2 == 1 ? 3 : 2) {
            var p = base(codeHold)
            p.flags = flagPending
            p.timeout = 3600
            pending.append(p)
            followups.append(resolution(of: p, flags: flagVoid))
        }
    } else { // 15 pendings expiring after 1s
        for _ in 0..<3 {
            var p = base(codeHold)
            p.flags = flagPending
            p.timeout = 1
            pending.append(p)
        }
    }
    batches.append(pending)

    if round % 3 == 0 { // linked group of 3 in one ledger
        let first = base(codePayment)
        let accs = byLedger[first.ledger]!
        var group = [first]
        for _ in 1..<3 {
            var t = base(codePayment)
            t.ledger = first.ledger
            t.debit = accs[rng.int(accs.count)].id
            t.credit = first.debit
            if t.debit == t.credit { t.debit = first.credit }
            group.append(t)
        }
        group[0].flags = flagLinked
        group[1].flags = flagLinked
        batches.append(group)
    }

    if followups.count >= 6 { // post/void land later in time than their pendings
        batches.append(followups)
        followups = []
    }
}
if !followups.isEmpty { batches.append(followups) }

batches.append((0..<10).map { _ in // 10 pendings that never expire
    var p = base(codeHold)
    p.flags = flagPending
    return p
})

// MARK: Run

let accountReply = client.submit(TB_OPERATION_CREATE_ACCOUNTS, accounts.flatMap(encode))
let (ac, ae, af) = tally(accountReply, created: TB_CREATE_ACCOUNT_CREATED.rawValue, exists: TB_CREATE_ACCOUNT_EXISTS.rawValue) { "account \(accounts[$0].id)" }
print("accounts: \(ac) created, \(ae) already existed, \(af) failed")

var tc = 0, te = 0, tf = 0
for batch in batches where !batch.isEmpty {
    let reply = client.submit(TB_OPERATION_CREATE_TRANSFERS, batch.flatMap(encode))
    let (c, e, f) = tally(reply, created: TB_CREATE_TRANSFER_CREATED.rawValue, exists: TB_CREATE_TRANSFER_EXISTS.rawValue) { "transfer \(batch[$0].id)" }
    tc += c; te += e; tf += f
}
print("transfers: \(tc) created, \(te) already existed, \(tf) failed (planned \(nextTransfer - 100_000))")

print("waiting for 1s-timeout pendings to expire…")
Thread.sleep(forTimeInterval: 3)
client.close()
print("done")
exit(af + tf == 0 ? 0 : 1)
