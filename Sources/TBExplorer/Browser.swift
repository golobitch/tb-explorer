import Foundation
import Observation
import TBKit

enum SidebarItem: Hashable {
    case overview
    case search
    case accounts
    case transfers
    case ledger(UInt32)
}

enum Route: Hashable {
    case ledger(UInt32)
    case account(UInt128)
    case transfer(UInt128)
}

/// One window's view of the cluster: what the sidebar has selected, and where this window has
/// navigated. The connection itself is shared (`Session`), so two windows can sit on two
/// different accounts without disturbing each other.
@MainActor
@Observable
final class Browser {
    let session: Session

    var sidebar: SidebarItem? = .overview {
        didSet { if oldValue != sidebar { history.reset() } }
    }
    var isGoToPresented = false

    private var history = NavigationHistory<Route>()

    /// The connection this window's navigation belongs to. Compared against the session's token
    /// rather than reset on every change, so navigating immediately after connecting — a deep
    /// link, or the debug launch arguments — is not undone by the reset that follows.
    private var seenToken = 0

    /// `init` stays free of side effects: SwiftUI evaluates `Browser()` on every re-declaration
    /// of the `@State` that holds it and discards all but the first.
    init(session: Session = .shared) {
        self.session = session
    }

    /// Bound to the `NavigationStack`, which also writes it directly — `adopt` reconciles that
    /// write so a route popped by its back button still becomes a forward entry. The guard is
    /// load-bearing: `@Observable` reports a mutation for any `mutating` call, even an inert one.
    var path: [Route] {
        get { history.stack }
        set {
            guard newValue != history.stack else { return }
            history.adopt(newValue)
        }
    }

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    func select(_ item: SidebarItem) {
        seenToken = session.connectionToken
        if case .ledger(let l) = item { session.observe(ledger: l) }
        sidebar = item
        history.reset()
    }

    func open(_ route: Route) {
        seenToken = session.connectionToken
        if case .ledger(let l) = route { session.observe(ledger: l) }
        history.push(route)
    }

    func goBack() {
        history.back()
    }

    func goForward() {
        history.forwardOne()
        if case .ledger(let l)? = history.stack.last { session.observe(ledger: l) }
    }

    /// Clears this window's navigation, e.g. when the cluster underneath it changes.
    func reset() {
        seenToken = session.connectionToken
        history.reset()
        sidebar = .overview
    }

    /// Routes name objects in one cluster, so a different connection starts this window over —
    /// unless this window has already navigated within the new connection.
    func connectionDidChange() {
        guard seenToken != session.connectionToken else { return }
        reset()
    }

    /// Writes a shareable link to this route on the pasteboard, stamped with the cluster so the
    /// other end cannot silently resolve a different object with the same id.
    func copyLink(_ route: Route) {
        copyToPasteboard(link(route).url(cluster: session.info?.clusterID).absoluteString)
    }

    private func link(_ route: Route) -> DeepLink {
        switch route {
        case .ledger(let l): .ledger(l)
        case .account(let id): .account(id)
        case .transfer(let id): .transfer(id)
        }
    }

    /// Navigates to the place a link names.
    func apply(_ link: DeepLink) {
        switch link {
        case .overview: select(.overview)
        case .search: select(.search)
        case .accounts: select(.accounts)
        case .transfers: select(.transfers)
        case .ledger(let l): select(.ledger(l))
        case .account(let id): open(.account(id))
        case .transfer(let id): open(.transfer(id))
        }
    }

    /// Resolves an id to an account or transfer and navigates to it.
    func goTo(_ raw: String) async throws {
        open(try await session.resolve(raw))
    }
}
