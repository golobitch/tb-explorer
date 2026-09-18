import AppKit
import SwiftUI
import TBKit

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

/// A full-precision id in monospaced digits, selectable, with a Copy context menu.
///
/// Two Swift pitfalls shape this view:
/// - It is used inside `Table` cells, which AppKit hosts and recycles separately, and
///   reading an `@Observable` value from the environment there traps. Parents pass `open`.
/// - A bare `UInt128` captured by an escaping closure can be miscompiled (its high 64 bits
///   read as garbage). The route is therefore a stored property read through `self`, and
///   `open` receives it as an argument (pass a method reference such as `browser.open`).
struct IDText: View {
    let id: UInt128
    var route: Route? = nil
    var open: ((Route) -> Void)? = nil

    var body: some View {
        let text = Text(String(id)).font(.body.monospaced()).textSelection(.enabled)
        Group {
            if let route, let open, id != 0 {
                RouteButton(route: route, open: open) { text.foregroundStyle(.link) }
                    .buttonStyle(.plain)
                    .help("Open \(String(id))")
            } else {
                text
            }
        }
        .contextMenu {
            Button("Copy ID") { copyToPasteboard(String(self.id)) }
            Button("Copy as Hex") { copyToPasteboard(self.id.hexString) }
            if let route, let open, id != 0 {
                Divider()
                RouteButton(route: route, open: open) { Text("Open") }
            }
        }
    }
}

/// A button that navigates to a route held as a stored property, so no 128-bit id is
/// captured by the action closure (see `IDText`).
struct RouteButton<Label: View>: View {
    let route: Route
    let open: (Route) -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: navigate, label: label)
    }

    private func navigate() {
        open(route)
    }
}

extension RouteButton where Label == Text {
    init(_ title: String, route: Route, open: @escaping (Route) -> Void) {
        self.init(route: route, open: open) { Text(title) }
    }
}

struct CopyButton: View {
    let value: String
    var help = "Copy"
    @State private var copied = false

    var body: some View {
        Button {
            copyToPasteboard(value)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

struct AmountText: View {
    let text: String
    var negative = false
    /// The exact integer, shown on hover when the amount is displayed scaled.
    var exact: String?

    init(_ v: UInt128) {
        text = TBFormat.amount(v)
    }

    init(_ v: SignedAmount) {
        text = TBFormat.amount(v)
        negative = v.isNegative && v.magnitude != 0
    }

    init(_ v: UInt128, ledger: UInt32, style: AmountStyle) {
        text = style.text(v, ledger: ledger)
        exact = style.alternate(v, ledger: ledger)
    }

    init(_ v: SignedAmount, ledger: UInt32, style: AmountStyle) {
        text = style.text(v, ledger: ledger)
        negative = v.isNegative && v.magnitude != 0
        exact = style.alternate(v, ledger: ledger)
    }

    var body: some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(negative ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .textSelection(.enabled)
            .help(exact ?? "")
    }
}

/// A dismissible strip explaining something that isn't an error: a lookup that found nothing,
/// a link waiting for a connection.
struct MessageBar: View {
    let text: String
    var symbol = "questionmark.circle"
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(text, systemImage: symbol)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help("Dismiss")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.4))
    }
}

/// Switches amounts between the ledger's currency format and exact integers.
/// One setting shown in several places, so every screen agrees on what a number means.
struct CurrencyFormatToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label("Currency Format", systemImage: "dollarsign.circle")
        }
        .help("Format amounts using the ledger's ISO 4217 currency (ledger 840 → USD, two decimals). Off shows exact integers.")
    }
}

/// A numeric `code` with its label from the connection's metadata, e.g. `10 · payment`.
struct CodeText: View {
    enum Kind { case transfer, account }

    let code: UInt16
    let kind: Kind
    let style: AmountStyle

    var body: some View {
        let label = kind == .transfer ? style.transferCodeLabel(code) : style.accountCodeLabel(code)
        Text(label)
            .monospacedDigit()
            .textSelection(.enabled)
            .help(label == String(code) ? "" : "Code \(code)")
    }
}

struct TimestampText: View {
    let ns: UInt64

    var body: some View {
        Text(TBFormat.timestamp(ns))
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .help("\(ns) ns since epoch")
    }
}

struct FlagsView: View {
    let names: [String]
    var emptyText = "—"

    var body: some View {
        if names.isEmpty {
            Text(emptyText).foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                ForEach(names, id: \.self) { FlagTag(name: $0) }
            }
        }
    }
}

struct FlagTag: View {
    let name: String

    private var tint: Color {
        switch name {
        case "pending": .orange
        case "post_pending_transfer": .green
        case "void_pending_transfer", "closed": .red
        case "linked": .purple
        case "history": .blue
        default: .secondary
        }
    }

    var body: some View {
        Text(name)
            .font(.caption)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: 4))
            .foregroundStyle(tint)
    }
}

struct StatusBadge: View {
    let status: PendingStatus

    var body: some View {
        let (label, tint, symbol): (String, Color, String) = switch status {
        case .posted: ("Posted", .green, "checkmark.circle.fill")
        case .voided: ("Voided", .red, "xmark.circle.fill")
        case .expired: ("Expired", .secondary, "clock.badge.xmark")
        case .pending: ("Pending", .orange, "hourglass")
        case .unknown: ("Unresolved in Lookback", .yellow, "questionmark.circle")
        }
        Label(label, systemImage: symbol)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
    }
}

struct ErrorBanner: View {
    let error: Error

    var body: some View {
        Label {
            Text(error.localizedDescription).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}

/// Footer under paginated tables: count, loading state and a manual Load More.
struct PageStatusBar<Item: Timestamped>: View {
    let list: PagedList<Item>
    let noun: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(list.items.count)\(list.hasMore ? "+" : "") \(noun)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if list.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            if list.hasMore, !list.isLoading, !list.items.isEmpty {
                Button("Load More") { Task { await list.loadMore() } }
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

extension View {
    /// Keeps a u32/u16 text field numeric while typing.
    func digitsOnly(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            let filtered = new.filter(\.isNumber)
            if filtered != new { text.wrappedValue = filtered }
        }
    }
}
