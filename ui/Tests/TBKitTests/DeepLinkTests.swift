import Foundation
import Testing
@testable import TBKit

@Suite("Deep links")
struct DeepLinkTests {
    private func parse(_ string: String) -> DeepLink? {
        URL(string: string).flatMap { DeepLink($0) }
    }

    private func parse(_ string: String, cluster: inout UInt128?) -> DeepLink? {
        guard let url = URL(string: string) else { return nil }
        return DeepLink(url, cluster: &cluster)
    }

    @Test func roundTripsEveryCase() {
        let links: [DeepLink] = [
            .overview, .search, .accounts, .transfers,
            .ledger(840), .account(1015), .transfer(100_539),
        ]
        for link in links {
            #expect(DeepLink(link.url()) == link, "\(link.url().absoluteString)")
        }
    }

    @Test func writesTheExpectedURL() {
        #expect(DeepLink.transfer(100_539).url().absoluteString == "tb-explorer://transfer/100539")
        #expect(DeepLink.accounts.url().absoluteString == "tb-explorer://accounts")
        #expect(
            DeepLink.account(1015).url(cluster: 7).absoluteString
                == "tb-explorer://account/1015?cluster=7")
    }

    @Test func carriesTheClusterWhenPresent() {
        var cluster: UInt128?
        #expect(parse("tb-explorer://transfer/100539?cluster=42", cluster: &cluster) == .transfer(100_539))
        #expect(cluster == 42)
    }

    @Test func leavesTheClusterUnsetWhenAbsent() {
        var cluster: UInt128?
        #expect(parse("tb-explorer://transfer/100539", cluster: &cluster) == .transfer(100_539))
        #expect(cluster == nil)
    }

    @Test func keepsFullPrecisionIDs() {
        let id = UInt128.max
        var cluster: UInt128?
        let url = DeepLink.account(id).url(cluster: .max)
        #expect(DeepLink(url, cluster: &cluster) == .account(id))
        #expect(cluster == .max)
    }

    @Test func acceptsHexIDs() {
        #expect(parse("tb-explorer://account/0xff") == .account(255))
    }

    /// The parser also reads `tb-explorer:transfer/100539`, but that spelling is not asserted:
    /// whether `URL(string:)` accepts it, and where it puts the first segment, varies by
    /// Foundation version. Everything the app produces and macOS delivers uses `//`.
    @Test func ignoresSchemeCase() {
        #expect(parse("TB-EXPLORER://Transfer/100539") == .transfer(100_539))
    }

    @Test func rejectsAnythingElse() {
        #expect(parse("https://example.com/transfer/100539") == nil)
        #expect(parse("tb-explorer://nonsense/1") == nil)
        #expect(parse("tb-explorer://transfer") == nil, "an id is required")
        #expect(parse("tb-explorer://account/not-a-number") == nil)
        #expect(parse("tb-explorer://ledger/99999999999") == nil, "a ledger is a u32")
    }

    @Test func rejectsAnUnparsableCluster() {
        var cluster: UInt128?
        #expect(parse("tb-explorer://transfer/1?cluster=abc", cluster: &cluster) == nil)
    }
}
