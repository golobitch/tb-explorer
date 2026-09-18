/// Back/forward history for a navigation stack that something else can also mutate.
///
/// `NavigationStack` writes its `path` binding directly — the back button in its toolbar pops a
/// route without going through `back()`. A forward stack maintained only by `back()` would
/// therefore go stale, so every write that arrives from the binding is reconciled by `adopt(_:)`.
///
/// Generic over `Item` and free of both SwiftUI and TigerBeetle, so it can be tested directly.
public struct NavigationHistory<Item: Equatable>: Equatable {
    /// Mirrors the navigation stack, root first.
    public private(set) var stack: [Item] = []
    /// Routes that were navigated away from, the next one to revisit last.
    public private(set) var forward: [Item] = []

    public init() {}

    public var canGoBack: Bool { !stack.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    /// Navigates to a new item, which abandons anything ahead.
    public mutating func push(_ item: Item) {
        guard stack.last != item else { return }
        stack.append(item)
        forward.removeAll()
    }

    public mutating func back() {
        guard let last = stack.popLast() else { return }
        forward.append(last)
    }

    public mutating func forwardOne() {
        guard let next = forward.popLast() else { return }
        stack.append(next)
    }

    public mutating func reset() {
        stack.removeAll()
        forward.removeAll()
    }

    /// Reconciles a stack written by the navigation container itself.
    ///
    /// A pop turns the removed routes into forward entries, innermost reachable first. A push of
    /// exactly the next forward entry consumes it; any other push abandons what was ahead.
    public mutating func adopt(_ new: [Item]) {
        if new == stack { return }

        if new.count < stack.count, Array(stack.prefix(new.count)) == new {
            forward.append(contentsOf: stack[new.count...].reversed())
            stack = new
            return
        }

        if new.count > stack.count, Array(new.prefix(stack.count)) == stack {
            let appended = Array(new[stack.count...])
            if appended.count == 1, forward.last == appended[0] {
                forward.removeLast()
            } else {
                forward.removeAll()
            }
            stack = new
            return
        }

        // Nothing in common: there is no meaningful way forward from here.
        stack = new
        forward.removeAll()
    }
}
