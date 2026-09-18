import Testing
@testable import TBKit

@Suite("Navigation history")
struct NavigationHistoryTests {
    private func history(_ items: String...) -> NavigationHistory<String> {
        var h = NavigationHistory<String>()
        for item in items { h.push(item) }
        return h
    }

    @Test func pushesAndPops() {
        var h = history("a", "b")
        #expect(h.stack == ["a", "b"])
        #expect(h.canGoBack)
        #expect(!h.canGoForward)

        h.back()
        #expect(h.stack == ["a"])
        #expect(h.canGoForward)

        h.forwardOne()
        #expect(h.stack == ["a", "b"])
        #expect(!h.canGoForward)
    }

    @Test func pushAbandonsWhatWasAhead() {
        var h = history("a", "b")
        h.back()
        h.push("c")
        #expect(h.stack == ["a", "c"])
        #expect(!h.canGoForward)
    }

    @Test func pushIgnoresTheItemAlreadyOnTop() {
        var h = history("a")
        h.push("a")
        #expect(h.stack == ["a"])
    }

    @Test func backOnAnEmptyStackDoesNothing() {
        var h = NavigationHistory<String>()
        h.back()
        h.forwardOne()
        #expect(h.stack.isEmpty)
        #expect(h.forward.isEmpty)
    }

    /// The navigation container's own back button pops the binding directly.
    @Test func adoptedPopBecomesForward() {
        var h = history("a", "b", "c")
        h.adopt(["a"])
        #expect(h.stack == ["a"])
        #expect(h.forward == ["c", "b"])

        h.forwardOne()
        #expect(h.stack == ["a", "b"])
        h.forwardOne()
        #expect(h.stack == ["a", "b", "c"])
        #expect(!h.canGoForward)
    }

    @Test func adoptingTheSameStackChangesNothing() {
        var h = history("a", "b")
        h.back()
        h.adopt(["a"])
        #expect(h.forward == ["b"])
    }

    @Test func adoptedPushConsumesTheMatchingForwardEntry() {
        var h = history("a", "b")
        h.back()
        h.adopt(["a", "b"])
        #expect(h.stack == ["a", "b"])
        #expect(!h.canGoForward)
    }

    @Test func adoptedPushOfSomethingElseAbandonsWhatWasAhead() {
        var h = history("a", "b")
        h.back()
        h.adopt(["a", "z"])
        #expect(h.stack == ["a", "z"])
        #expect(!h.canGoForward)
    }

    @Test func adoptedDivergenceAbandonsWhatWasAhead() {
        var h = history("a", "b", "c")
        h.back()
        h.adopt(["x", "y"])
        #expect(h.stack == ["x", "y"])
        #expect(!h.canGoForward)
    }

    @Test func resetClearsBothDirections() {
        var h = history("a", "b")
        h.back()
        h.reset()
        #expect(h.stack.isEmpty)
        #expect(!h.canGoBack)
        #expect(!h.canGoForward)
    }
}
