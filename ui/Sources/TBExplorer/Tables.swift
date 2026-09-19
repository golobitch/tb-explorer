import SwiftUI
import TBKit

struct AccountsTable: View {
    let list: PagedList<Account>
    let emptyText: String
    /// Read once here in the parent; never inside a cell.
    var style: AmountStyle = .raw
    @Environment(Browser.self) private var browser
    @State private var selection = Set<UInt128>()

    var body: some View {
        VStack(spacing: 0) {
            Table(list.items, selection: $selection) {
                TableColumn("ID") { a in
                    Text(String(a.id))
                        .font(.body.monospaced())
                        .onAppear { list.loadMoreIfNeeded(after: a) }
                }
                .width(min: 80, ideal: 140)
                TableColumn("Code") { a in CodeText(code: a.code, kind: .account, style: style) }
                    .width(min: 40, ideal: 70)
                TableColumn("Flags") { a in FlagsView(names: a.flags.names) }
                    .width(min: 60, ideal: 110)
                TableColumn("Debits Pending") { a in
                    AmountText(a.debitsPending, ledger: a.ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Debits Posted") { a in
                    AmountText(a.debitsPosted, ledger: a.ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Credits Pending") { a in
                    AmountText(a.creditsPending, ledger: a.ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Credits Posted") { a in
                    AmountText(a.creditsPosted, ledger: a.ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Net (Cr − Dr)") { a in
                    AmountText(a.netPosted, ledger: a.ledger, style: style)
                        .fontWeight(.medium).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Timestamp") { a in TimestampText(ns: a.timestamp) }
                    .width(min: 150, ideal: 220)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UInt128.self) { ids in
                if ids.count == 1, let id = ids.first {
                    RouteButton("Open Account", route: .account(id), open: browser.open)
                    RouteButton("Copy Link", route: .account(id), open: browser.copyLink)
                    Divider()
                }
                Button(ids.count == 1 ? "Copy ID" : "Copy \(ids.count) IDs") {
                    copyToPasteboard(ids.sorted().map { String($0) }.joined(separator: "\n"))
                }
            } primaryAction: { ids in
                if let id = ids.first { browser.open(.account(id)) }
            }
            .overlay { TableOverlay(list: list, emptyText: emptyText) }
            Divider()
            PageStatusBar(list: list, noun: "accounts")
        }
        .onCopyCommand {
            [NSItemProvider(object: selection.sorted().map { String($0) }.joined(separator: "\n") as NSString)]
        }
    }
}

struct TransfersTable: View {
    let list: PagedList<Transfer>
    /// When set, adds a Side column relative to this account.
    var perspective: UInt128?
    let emptyText: String
    /// Read once here in the parent; never inside a cell.
    var style: AmountStyle = .raw
    @Environment(Browser.self) private var browser
    @State private var selection = Set<UInt128>()

    var body: some View {
        VStack(spacing: 0) {
            Table(list.items, selection: $selection) {
                TableColumn("ID") { t in
                    Text(String(t.id))
                        .font(.body.monospaced())
                        .onAppear { list.loadMoreIfNeeded(after: t) }
                }
                .width(min: 80, ideal: 130)
                TableColumn(perspective == nil ? "Ledger" : "Side") { t in
                    if let perspective {
                        Text(t.debitAccountID == perspective ? "Debit" : "Credit")
                            .foregroundStyle(t.debitAccountID == perspective ? .orange : .teal)
                    } else {
                        Text(style.ledgerLabel(t.ledger)).monospacedDigit()
                    }
                }
                .width(min: 50, ideal: 90)
                TableColumn("Debit Account") { t in
                    IDText(
                        id: t.debitAccountID, route: .account(t.debitAccountID),
                        open: browser.open, copyLink: browser.copyLink)
                }
                .width(min: 80, ideal: 130)
                TableColumn("Credit Account") { t in
                    IDText(
                        id: t.creditAccountID, route: .account(t.creditAccountID),
                        open: browser.open, copyLink: browser.copyLink)
                }
                .width(min: 80, ideal: 130)
                TableColumn("Amount") { t in
                    AmountText(t.amount, ledger: t.ledger, style: style).frame(maxWidth: .infinity, alignment: .trailing)
                }
                TableColumn("Code") { t in CodeText(code: t.code, kind: .transfer, style: style) }
                    .width(min: 40, ideal: 70)
                TableColumn("Flags") { t in FlagsView(names: t.flags.names) }
                    .width(min: 60, ideal: 160)
                TableColumn("Timestamp") { t in TimestampText(ns: t.timestamp) }
                    .width(min: 150, ideal: 220)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UInt128.self) { ids in
                if ids.count == 1, let id = ids.first, let t = list.items.first(where: { $0.id == id }) {
                    RouteButton("Open Transfer", route: .transfer(id), open: browser.open)
                    RouteButton("Copy Link", route: .transfer(id), open: browser.copyLink)
                    RouteButton("Open Debit Account", route: .account(t.debitAccountID), open: browser.open)
                    RouteButton("Open Credit Account", route: .account(t.creditAccountID), open: browser.open)
                    if t.pendingID != 0 {
                        RouteButton("Open Pending Transfer", route: .transfer(t.pendingID), open: browser.open)
                    }
                    Divider()
                }
                Button(ids.count == 1 ? "Copy ID" : "Copy \(ids.count) IDs") {
                    copyToPasteboard(ids.sorted().map { String($0) }.joined(separator: "\n"))
                }
            } primaryAction: { ids in
                if let id = ids.first { browser.open(.transfer(id)) }
            }
            .overlay { TableOverlay(list: list, emptyText: emptyText) }
            Divider()
            PageStatusBar(list: list, noun: "transfers")
        }
        .onCopyCommand {
            [NSItemProvider(object: selection.sorted().map { String($0) }.joined(separator: "\n") as NSString)]
        }
    }
}

private struct TableOverlay<Item: Timestamped>: View {
    let list: PagedList<Item>
    let emptyText: String

    var body: some View {
        if let error = list.error, list.items.isEmpty {
            ContentUnavailableView {
                Label("Query Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await list.reload() } }
            }
        } else if list.items.isEmpty, list.isLoading {
            ProgressView()
        } else if list.items.isEmpty, !list.hasMore {
            ContentUnavailableView(emptyText, systemImage: "tray")
        }
    }
}
