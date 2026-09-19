import Foundation
import Testing
@testable import TBKit

/// Runs against a cluster seeded by `tb-seed`. Enabled by `TB_ADDRESS`
/// (pass `TEST_RUNNER_TB_ADDRESS=host:port` to xcodebuild, or `make integration`).
private let address = ProcessInfo.processInfo.environment["TB_ADDRESS"]

@Suite("Integration", .enabled(if: address != nil, "set TB_ADDRESS to run"), .serialized)
struct IntegrationTests {
    let client: TBClient

    init() async throws {
        (client, _) = try await TBClient.connect(clusterID: 0, addresses: [address!])
    }

    @Test func connectReportsVersionAndLatency() async throws {
        let (c, info) = try await TBClient.connect(clusterID: 0, addresses: [address!])
        defer { c.close() }
        #expect(info.clientVersion == TBClient.clientVersion)
        #expect(info.latency < .seconds(1))
    }

    @Test func unreachableClusterTimesOut() async {
        await #expect(throws: TBError.timeout(.milliseconds(500))) {
            _ = try await TBClient.connect(clusterID: 0, addresses: ["127.0.0.1:1"], timeout: .milliseconds(500))
        }
    }

    @Test("query_accounts paginates by timestamp cursor", arguments: [(UInt32(700), 12), (UInt32(840), 8)])
    func paginateAccounts(ledger: UInt32, expected: Int) async throws {
        var seen = Set<UInt128>()
        var filter = QueryFilter(ledger: ledger, limit: 5)
        while true {
            let page = try await client.queryAccounts(filter)
            for a in page {
                #expect(a.ledger == ledger)
                #expect(seen.insert(a.id).inserted, "duplicate \(a.id)")
            }
            guard page.count == 5, let last = page.last else { break }
            filter.timestampMin = last.timestamp + 1
        }
        #expect(seen.count == expected)
    }

    @Test func accountTransfersAndBalances() async throws {
        let accounts = try await client.queryAccounts(QueryFilter(ledger: 700, limit: 100))
        var withHistory = 0
        for a in accounts {
            let all = try await client.accountTransfers(a.id, AccountFilter(limit: tbMaxLimit))
            #expect(!all.isEmpty)
            let debits = try await client.accountTransfers(a.id, AccountFilter(debits: true, credits: false, limit: tbMaxLimit))
            #expect(debits.allSatisfy { $0.debitAccountID == a.id })
            let balances = try await client.accountBalances(a.id, AccountFilter(limit: tbMaxLimit))
            if a.flags.contains(.history) {
                withHistory += 1
                #expect(!balances.isEmpty)
                let last = try #require(balances.last)
                #expect(last.debitsPosted == a.debitsPosted && last.creditsPosted == a.creditsPosted)
                let source = try await client.transfer(atTimestamp: last.timestamp)
                #expect(source != nil)
            } else {
                #expect(balances.isEmpty)
            }
        }
        #expect(withHistory > 0 && withHistory < accounts.count)
    }

    @Test func accountTransfersFilterCombinations() async throws {
        for reversed in [false, true] {
            for (debits, credits) in [(true, true), (true, false), (false, true)] {
                let page = try await client.accountTransfers(1001, AccountFilter(
                    debits: debits, credits: credits, timestampMin: 0, timestampMax: 0,
                    limit: 100, reversed: reversed))
                #expect(!page.isEmpty, "reversed=\(reversed) debits=\(debits) credits=\(credits)")
                if reversed, page.count > 1 {
                    #expect(page[0].timestamp > page[1].timestamp, "reversed order")
                }
            }
        }
    }

    @Test func findTransferRelativeToAccount() async throws {
        let t = try await client.lookupTransfer(100_011)
        #expect(try await client.findTransfer(100_011, onAccount: t.debitAccountID) == .onAccount(t))
        #expect(try await client.findTransfer(100_011, onAccount: t.creditAccountID) == .onAccount(t))
        let unrelated = try #require((1001...1020).map { UInt128($0) }.first { $0 != t.debitAccountID && $0 != t.creditAccountID })
        #expect(try await client.findTransfer(100_011, onAccount: unrelated) == .otherAccounts(t))
        #expect(try await client.findTransfer(.max, onAccount: t.debitAccountID) == .notFound)
    }

    @Test func accountTransfersFilterByCode() async throws {
        let all = try await client.accountTransfers(1001, AccountFilter(limit: tbMaxLimit))
        let holds = try await client.accountTransfers(1001, AccountFilter(code: 20, limit: tbMaxLimit))
        #expect(!holds.isEmpty)
        #expect(holds.allSatisfy { $0.code == 20 })
        #expect(holds.count == all.filter { $0.code == 20 }.count)
    }

    @Test func pendingChains() async throws {
        let holds = try await client.queryTransfers(QueryFilter(code: 20, limit: tbMaxLimit))
        var counts: [PendingStatus: Int] = [:]
        for h in holds {
            let chain = try await client.chain(for: h.id)
            if h.flags.contains(.pending) {
                let status = try #require(chain.resolution).status
                counts[status, default: 0] += 1
                switch h.timeout {
                case 0: #expect(status == .pending)
                case 1: #expect(status == .expired)
                default: #expect(status == .posted || status == .voided)
                }
            } else {
                #expect(chain.pending?.id == h.pendingID, "resolution \(h.id) must link to its pending")
            }
        }
        #expect(counts == [.posted: 40, .voided: 25, .expired: 15, .pending: 10])
    }

    @Test func linkedGroups() async throws {
        let payments = try await client.queryTransfers(QueryFilter(code: 10, limit: tbMaxLimit))
        let linked = payments.filter { $0.flags.contains(.linked) }
        #expect(!linked.isEmpty)
        for t in linked {
            let chain = try await client.chain(for: t.id)
            #expect(chain.linked.count == 3, "transfer \(t.id)")
            #expect(chain.linked.last.map { !$0.flags.contains(.linked) } == true)
        }
    }

    @Test func lookupIDDetectsKind() async throws {
        guard case .account = try await client.lookupID(1001) else { Issue.record("1001 should be an account"); return }
        guard case .transfer = try await client.lookupID(100_001) else { Issue.record("100001 should be a transfer"); return }
        #expect(try await client.lookupID(.max) == .none)
    }
}
