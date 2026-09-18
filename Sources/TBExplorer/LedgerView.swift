import SwiftUI
import TBKit

/// Optional query_* filter fields as typed by the user. Parsed on apply.
struct FilterFields: Equatable {
    var ledger = ""
    var code = ""
    var userData128 = ""
    var userData64 = ""
    var userData32 = ""

    struct Parsed: Equatable, Sendable {
        var ledger: UInt32 = 0
        var code: UInt16 = 0
        var userData128: UInt128 = 0
        var userData64: UInt64 = 0
        var userData32: UInt32 = 0
    }

    func parse() throws -> Parsed {
        var p = Parsed()
        if !ledger.isEmpty {
            guard let v = UInt32(ledger) else { throw TBError.unexpected("Ledger must be 0–4294967295.") }
            p.ledger = v
        }
        if !code.isEmpty {
            guard let v = UInt16(code) else { throw TBError.unexpected("Code must be 0–65535.") }
            p.code = v
        }
        if !userData128.isEmpty {
            guard let v = UInt128(tbString: userData128) else { throw TBError.unexpected("user_data_128 must be a u128.") }
            p.userData128 = v
        }
        if !userData64.isEmpty {
            guard let v = UInt128(tbString: userData64), v <= UInt128(UInt64.max) else {
                throw TBError.unexpected("user_data_64 must be a u64.")
            }
            p.userData64 = UInt64(v)
        }
        if !userData32.isEmpty {
            guard let v = UInt32(userData32) else { throw TBError.unexpected("user_data_32 must be a u32.") }
            p.userData32 = v
        }
        return p
    }
}

struct FilterBar: View {
    enum Field: Hashable { case ledger, code, userData128, userData64, userData32 }

    @Binding var fields: FilterFields
    /// Shown on cluster-wide lists; ledger screens and account tabs already scope it.
    var showsLedger = false
    /// The screen's ⌘F target. Screens that don't publish one simply never take focus.
    var focus: FilterFocus? = nil
    let onApply: () -> Void
    @FocusState private var focused: Field?

    var body: some View {
        HStack(spacing: 8) {
            if showsLedger {
                field("Ledger", .ledger, $fields.ledger, width: 90, digits: true)
            }
            field("Code", .code, $fields.code, width: 70, digits: true)
            field("user_data_128", .userData128, $fields.userData128, width: 200)
            field("user_data_64", .userData64, $fields.userData64, width: 150)
            field("user_data_32", .userData32, $fields.userData32, width: 100, digits: true)
            Button("Apply", action: onApply)
            if fields != FilterFields() {
                Button("Clear") {
                    fields = FilterFields()
                    onApply()
                }
                .buttonStyle(.borderless)
            }
            Spacer()
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: focus?.token) { focused = showsLedger ? .ledger : .code }
        #if DEBUG
        // `-TBFilterFocus YES` drives the same request ⌘F sends, for screenshots.
        .task {
            guard UserDefaults.standard.bool(forKey: "TBFilterFocus") else { return }
            try? await Task.sleep(for: .seconds(2))
            focus?.request()
        }
        #endif
    }

    private func field(
        _ title: String, _ id: Field, _ text: Binding<String>, width: CGFloat, digits: Bool = false
    ) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.callout.monospaced())
            .frame(width: width)
            .focused($focused, equals: id)
            .onSubmit(onApply)
            .modifier(DigitsModifier(enabled: digits, text: text))
    }
}

private struct DigitsModifier: ViewModifier {
    let enabled: Bool
    let text: Binding<String>

    func body(content: Content) -> some View {
        if enabled { content.digitsOnly(text) } else { content }
    }
}

struct LedgerView: View {
    let ledger: UInt32
    @Environment(Session.self) private var session
    @State private var fields = FilterFields()
    @State private var applied = FilterFields.Parsed()
    @State private var filterError: Error?
    @AppStorage("ledger.newestFirst") private var newestFirst = false
    @AppStorage("format.currency") private var currencyFormat = true
    @State private var list = PagedList<Account>()
    @State private var filterFocus = FilterFocus()

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(fields: $fields, focus: filterFocus, onApply: apply)
            if let filterError {
                ErrorBanner(error: filterError).padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            AccountsTable(
                list: list, emptyText: "No Accounts in Ledger \(ledger)",
                style: session.amountStyle(currency: currencyFormat))
        }
        .focusedSceneValue(filterFocus)
        .navigationTitle(session.amountStyle(currency: currencyFormat).ledgerLabel(ledger))
        .navigationSubtitle("query_accounts")
        .toolbar {
            ToolbarItemGroup {
                CurrencyFormatToggle(isOn: $currencyFormat)
                Toggle(isOn: $newestFirst) {
                    Label("Newest First", systemImage: "arrow.up.arrow.down")
                }
                .help("Newest First")
                Button { Task { await list.reload() } } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
            }
        }
        .task(id: QueryKey(ledger: ledger, filter: applied, reversed: newestFirst)) {
            session.observe(ledger: ledger)
            guard let client = session.client else { return }
            let f = applied
            await list.reset(
                source: QueryAccountsSource(
                    client: client,
                    base: QueryFilter(
                        ledger: ledger, code: f.code, userData128: f.userData128,
                        userData64: f.userData64, userData32: f.userData32, reversed: newestFirst)),
                reversed: newestFirst)
        }
    }

    private func apply() {
        do {
            applied = try fields.parse()
            filterError = nil
        } catch {
            filterError = error
        }
    }
}

private struct QueryKey: Hashable {
    let ledger: UInt32
    let filter: FilterFields.Parsed
    let reversed: Bool
}

extension FilterFields.Parsed: Hashable {}

extension FilterFields.Parsed {
    func queryFilter(reversed: Bool) -> QueryFilter {
        QueryFilter(
            ledger: ledger, code: code, userData128: userData128, userData64: userData64,
            userData32: userData32, reversed: reversed)
    }
}
