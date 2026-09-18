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

        // `tb-explorer://transfer/100539` puts "transfer" in the host and "/100539" in the path,
        // while `tb-explorer:transfer/100539` puts both in the path.
        var parts = [url.host()].compactMap { $0 }
        parts += url.pathComponents.filter { $0 != "/" }
        guard let kind = parts.first?.lowercased() else { return nil }
        let argument = parts.count > 1 ? parts[1] : nil

        if let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "cluster" })?.value {
            guard let parsed = UInt128(tbString: raw) else { return nil }
            cluster = parsed
        }

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
