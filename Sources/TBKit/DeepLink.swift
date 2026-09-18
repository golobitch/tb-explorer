import Foundation

/// A location in the app that can be written down: `tb-explorer://transfer/100539?cluster=0`.
///
/// The cluster is part of the link because TigerBeetle ids are only unique within a cluster —
/// without it, a link from someone else's cluster would resolve a different object with the same
/// id and look perfectly convincing. A link names a place, never how to reach it: it carries no
/// addresses, so opening one can never make the app connect anywhere.
public enum DeepLink: Equatable, Sendable {
    case overview
    case search
    case accounts
    case transfers
    case ledger(UInt32)
    case account(UInt128)
    case transfer(UInt128)

    public static let scheme = "tb-explorer"

    public init?(_ url: URL, cluster: inout UInt128?) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }

        // Read the location out of the string rather than from `host` and `pathComponents`:
        // Foundation versions disagree about whether the first segment of
        // `tb-explorer:transfer/100539` is a host or the start of the path, and this grammar is
        // small enough that the disagreement is not worth inheriting.
        var rest = Substring(url.absoluteString).dropFirst(Self.scheme.count + 1)
        if rest.hasPrefix("//") { rest = rest.dropFirst(2) }

        var query = Substring("")
        if let mark = rest.firstIndex(of: "?") {
            query = rest[rest.index(after: mark)...]
            rest = rest[..<mark]
        }

        if let raw = query.split(separator: "&").first(where: { $0.hasPrefix("cluster=") }) {
            guard let parsed = UInt128(tbString: String(raw.dropFirst("cluster=".count))) else { return nil }
            cluster = parsed
        }

        let parts = rest.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        guard let kind = parts.first?.lowercased() else { return nil }
        let argument = parts.count > 1 ? parts[1] : nil

        switch (kind, argument) {
        case ("overview", _): self = .overview
        case ("search", _): self = .search
        case ("accounts", _): self = .accounts
        case ("transfers", _): self = .transfers
        case ("ledger", let id?):
            guard let value = UInt32(id) else { return nil }
            self = .ledger(value)
        case ("account", let id?):
            guard let value = UInt128(tbString: id) else { return nil }
            self = .account(value)
        case ("transfer", let id?):
            guard let value = UInt128(tbString: id) else { return nil }
            self = .transfer(value)
        default: return nil
        }
    }

    /// Convenience for callers that don't care which cluster the link names.
    public init?(_ url: URL) {
        var cluster: UInt128?
        self.init(url, cluster: &cluster)
    }

    public func url(cluster: UInt128? = nil) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = kind
        if let id { components.path = "/\(id)" }
        if let cluster { components.queryItems = [URLQueryItem(name: "cluster", value: String(cluster))] }
        // Every component is generated from a fixed vocabulary and decimal digits.
        return components.url!
    }

    private var kind: String {
        switch self {
        case .overview: "overview"
        case .search: "search"
        case .accounts: "accounts"
        case .transfers: "transfers"
        case .ledger: "ledger"
        case .account: "account"
        case .transfer: "transfer"
        }
    }

    private var id: String? {
        switch self {
        case .overview, .search, .accounts, .transfers: nil
        case .ledger(let l): String(l)
        case .account(let id), .transfer(let id): String(id)
        }
    }
}
