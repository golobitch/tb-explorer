import Foundation

/// A currency from the ISO 4217 list.
///
/// `exponent` is the currency's minor unit: the number of digits after the decimal point
/// (2 for USD, 0 for JPY, 3 for BHD). It is what makes an integer amount readable.
public struct ISOCurrency: Sendable, Hashable {
    public let numeric: UInt32
    public let alpha: String
    public let exponent: UInt8
    /// Only the widely recognised ones; elsewhere the alpha code reads better than a glyph.
    public let symbol: String?

    public init(numeric: UInt32, alpha: String, exponent: UInt8, symbol: String? = nil) {
        self.numeric = numeric
        self.alpha = alpha
        self.exponent = exponent
        self.symbol = symbol
    }
}

/// Maps a TigerBeetle ledger id to a currency, assuming the ledger uses ISO 4217 numeric codes.
///
/// This is a convention, not a rule: a ledger id is just a `u32`. The app treats a match as a
/// default that the user can override or switch off, never as a statement of fact.
public enum ISO4217 {
    /// Active ISO 4217 codes (numeric, alpha, minor units). Withdrawn codes are omitted, so a
    /// ledger numbered after a retired currency simply has no match.
    private static let entries: [(UInt32, String, UInt8, String?)] = [
        (8, "ALL", 2, nil), (12, "DZD", 2, nil), (32, "ARS", 2, nil), (36, "AUD", 2, "A$"),
        (44, "BSD", 2, nil), (48, "BHD", 3, nil), (50, "BDT", 2, "৳"), (51, "AMD", 2, "֏"),
        (52, "BBD", 2, nil), (60, "BMD", 2, nil), (64, "BTN", 2, nil), (68, "BOB", 2, nil),
        (72, "BWP", 2, nil), (84, "BZD", 2, nil), (90, "SBD", 2, nil), (96, "BND", 2, nil),
        (104, "MMK", 2, nil), (108, "BIF", 0, nil), (116, "KHR", 2, "៛"), (124, "CAD", 2, "C$"),
        (132, "CVE", 2, nil), (136, "KYD", 2, nil), (144, "LKR", 2, nil), (152, "CLP", 0, nil),
        (156, "CNY", 2, "¥"), (170, "COP", 2, nil), (174, "KMF", 0, nil), (188, "CRC", 2, "₡"),
        (192, "CUP", 2, nil), (203, "CZK", 2, "Kč"), (208, "DKK", 2, "kr"), (214, "DOP", 2, nil),
        (222, "SVC", 2, nil), (230, "ETB", 2, nil), (232, "ERN", 2, nil), (238, "FKP", 2, nil),
        (242, "FJD", 2, nil), (262, "DJF", 0, nil), (270, "GMD", 2, nil), (292, "GIP", 2, nil),
        (320, "GTQ", 2, nil), (324, "GNF", 0, nil), (328, "GYD", 2, nil), (332, "HTG", 2, nil),
        (340, "HNL", 2, nil), (344, "HKD", 2, "HK$"), (348, "HUF", 2, "Ft"), (352, "ISK", 0, nil),
        (356, "INR", 2, "₹"), (360, "IDR", 2, "Rp"), (364, "IRR", 2, nil), (368, "IQD", 3, nil),
        (376, "ILS", 2, "₪"), (388, "JMD", 2, nil), (392, "JPY", 0, "¥"), (398, "KZT", 2, "₸"),
        (400, "JOD", 3, nil), (404, "KES", 2, nil), (408, "KPW", 2, nil), (410, "KRW", 0, "₩"),
        (414, "KWD", 3, nil), (417, "KGS", 2, nil), (418, "LAK", 2, nil), (422, "LBP", 2, nil),
        (426, "LSL", 2, nil), (430, "LRD", 2, nil), (434, "LYD", 3, nil), (446, "MOP", 2, nil),
        (454, "MWK", 2, nil), (458, "MYR", 2, "RM"), (462, "MVR", 2, nil), (480, "MUR", 2, nil),
        (484, "MXN", 2, "$"), (496, "MNT", 2, "₮"), (498, "MDL", 2, nil), (504, "MAD", 2, nil),
        (512, "OMR", 3, nil), (516, "NAD", 2, nil), (524, "NPR", 2, nil), (532, "ANG", 2, nil),
        (533, "AWG", 2, nil), (548, "VUV", 0, nil), (554, "NZD", 2, "NZ$"), (558, "NIO", 2, nil),
        (566, "NGN", 2, "₦"), (578, "NOK", 2, "kr"), (586, "PKR", 2, nil), (590, "PAB", 2, nil),
        (598, "PGK", 2, nil), (600, "PYG", 0, "₲"), (604, "PEN", 2, nil), (608, "PHP", 2, "₱"),
        (634, "QAR", 2, nil), (643, "RUB", 2, "₽"), (646, "RWF", 0, nil), (654, "SHP", 2, nil),
        (682, "SAR", 2, nil), (690, "SCR", 2, nil), (702, "SGD", 2, "S$"), (704, "VND", 0, "₫"),
        (706, "SOS", 2, nil), (710, "ZAR", 2, "R"), (728, "SSP", 2, nil), (748, "SZL", 2, nil),
        (752, "SEK", 2, "kr"), (756, "CHF", 2, nil), (760, "SYP", 2, nil), (764, "THB", 2, "฿"),
        (776, "TOP", 2, nil), (780, "TTD", 2, nil), (784, "AED", 2, nil), (788, "TND", 3, nil),
        (800, "UGX", 0, nil), (807, "MKD", 2, nil), (818, "EGP", 2, nil), (826, "GBP", 2, "£"),
        (834, "TZS", 2, nil), (840, "USD", 2, "$"), (858, "UYU", 2, nil), (860, "UZS", 2, nil),
        (882, "WST", 2, nil), (886, "YER", 2, nil), (901, "TWD", 2, "NT$"), (924, "ZWG", 2, nil),
        (925, "SLE", 2, nil), (926, "VED", 2, nil), (927, "UYW", 4, nil), (928, "VES", 2, nil),
        (929, "MRU", 2, nil), (930, "STN", 2, nil), (931, "CUC", 2, nil), (933, "BYN", 2, nil),
        (934, "TMT", 2, nil), (936, "GHS", 2, nil), (938, "SDG", 2, nil), (940, "UYI", 0, nil),
        (941, "RSD", 2, nil), (943, "MZN", 2, nil), (944, "AZN", 2, "₼"), (946, "RON", 2, nil),
        (947, "CHE", 2, nil), (948, "CHW", 2, nil), (949, "TRY", 2, "₺"), (950, "XAF", 0, nil),
        (951, "XCD", 2, nil), (952, "XOF", 0, nil), (953, "XPF", 0, nil), (955, "XBA", 0, nil),
        (956, "XBB", 0, nil), (957, "XBC", 0, nil), (958, "XBD", 0, nil), (960, "XDR", 0, nil),
        (961, "XAG", 0, nil), (962, "XPT", 0, nil), (964, "XPD", 0, nil), (965, "XUA", 0, nil),
        (967, "ZMW", 2, nil), (968, "SRD", 2, nil), (969, "MGA", 2, nil), (970, "COU", 2, nil),
        (971, "AFN", 2, "؋"), (972, "TJS", 2, nil), (973, "AOA", 2, nil), (975, "BGN", 2, nil),
        (976, "CDF", 2, nil), (977, "BAM", 2, nil), (978, "EUR", 2, "€"), (979, "MXV", 2, nil),
        (980, "UAH", 2, "₴"), (981, "GEL", 2, "₾"), (984, "BOV", 2, nil), (985, "PLN", 2, "zł"),
        (986, "BRL", 2, "R$"), (990, "CLF", 4, nil), (994, "XSU", 0, nil), (997, "USN", 2, nil),
        (999, "XXX", 0, nil),
    ]

    private static let byNumeric: [UInt32: ISOCurrency] = Dictionary(
        uniqueKeysWithValues: entries.map {
            ($0.0, ISOCurrency(numeric: $0.0, alpha: $0.1, exponent: $0.2, symbol: $0.3))
        })

    /// The currency whose ISO 4217 numeric code equals this ledger id, if any.
    public static func currency(forLedger id: UInt32) -> ISOCurrency? {
        byNumeric[id]
    }

    /// Every known currency, ordered by alpha code. Used by the settings picker.
    public static var all: [ISOCurrency] {
        byNumeric.values.sorted { $0.alpha < $1.alpha }
    }
}
