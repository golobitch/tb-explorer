import Foundation
import TBKit

/// Preferences that change how queries are made rather than how they are drawn.
///
/// Read at the point of use rather than observed: a new page size should apply to the next page,
/// not invalidate every table and refetch the moment the stepper moves. `0` means "unset", which
/// is how an untouched `UserDefaults` integer already reads.
enum AppSettings {
    static let rowsPerPageKey = "general.rowsPerPage"
    static let lookbackKey = "general.lookback"
    static let startupModeKey = "general.startupMode"
    static let startupConnectionKey = "general.startupConnection"
    static let restoreLocationKey = "general.restoreLastLocation"
    static let lastLocationKey = "general.lastLocation"

    static var rowsPerPage: UInt32 {
        clampLimit(UInt32(clamping: UserDefaults.standard.integer(forKey: rowsPerPageKey)))
    }

    static var lookback: UInt32 {
        let stored = UInt32(clamping: UserDefaults.standard.integer(forKey: lookbackKey))
        return stored == 0 ? TBClient.defaultLookback : min(stored, TBClient.maxLookback)
    }
}

/// What the app does with a connection when it launches.
enum StartupMode: String, CaseIterable, Identifiable {
    case ask
    case lastUsed
    case specific

    var id: Self { self }

    var title: String {
        switch self {
        case .ask: "Ask every time"
        case .lastUsed: "Reopen the last connection"
        case .specific: "Always use"
        }
    }
}
