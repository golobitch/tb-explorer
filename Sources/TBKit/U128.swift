import Foundation

extension UInt128 {
    /// Parses a decimal or `0x`-prefixed hex string. Underscores, commas and spaces are ignored.
    public init?(tbString raw: String) {
        let s = raw.filter { !"_, \u{2009}\u{00A0}".contains($0) }
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            let hex = s.dropFirst(2)
            guard !hex.isEmpty, hex.count <= 32, let v = UInt128(hex, radix: 16) else { return nil }
            self = v
        } else {
            guard s.allSatisfy(\.isASCII), let v = UInt128(s, radix: 10) else { return nil }
            self = v
        }
    }

    public var hexString: String { "0x" + String(self, radix: 16) }
}

/// A signed amount with a full u128 magnitude, e.g. credits − debits.
/// `Int128` cannot represent every difference of two u128 values.
public struct SignedAmount: Hashable, Sendable, Comparable {
    public let magnitude: UInt128
    public let isNegative: Bool

    public init(credits: UInt128, debits: UInt128) {
        if credits >= debits {
            magnitude = credits - debits
            isNegative = false
        } else {
            magnitude = debits - credits
            isNegative = true
        }
    }

    public static func < (a: SignedAmount, b: SignedAmount) -> Bool {
        switch (a.isNegative, b.isNegative) {
        case (true, false): return true
        case (false, true): return false
        case (false, false): return a.magnitude < b.magnitude
        case (true, true): return a.magnitude > b.magnitude
        }
    }

    /// Lossy conversion for plotting only.
    public var doubleValue: Double {
        let d = Double(magnitude)
        return isNegative ? -d : d
    }
}

public enum TBFormat {
    /// Groups digits of an exact u128 using the given separator (locale grouping by default).
    public static func amount(_ v: UInt128, separator: String = Locale.current.groupingSeparator ?? ",") -> String {
        group(String(v), separator: separator)
    }

    public static func amount(_ v: SignedAmount, separator: String = Locale.current.groupingSeparator ?? ",") -> String {
        let body = amount(v.magnitude, separator: separator)
        return v.isNegative && v.magnitude != 0 ? "−" + body : body
    }

    static func group(_ digits: String, separator: String) -> String {
        guard digits.count > 3 else { return digits }
        var out: [Character] = []
        out.reserveCapacity(digits.count + digits.count / 3 * separator.count)
        for (i, c) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(contentsOf: separator) }
            out.append(c)
        }
        return String(out)
    }

    /// A single-unit latency, e.g. `14.08 ms` or `812 µs`.
    public static func latency(_ d: Duration) -> String {
        let ms = Double(d.components.seconds) * 1_000 + Double(d.components.attoseconds) / 1e15
        if ms >= 1_000 { return (ms / 1_000).formatted(.number.precision(.fractionLength(2))) + " s" }
        if ms >= 1 { return ms.formatted(.number.precision(.fractionLength(2))) + " ms" }
        return (ms * 1_000).formatted(.number.precision(.fractionLength(0))) + " µs"
    }

    /// TigerBeetle timestamps are nanoseconds since the Unix epoch.
    public static func date(_ ns: UInt64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ns / 1_000_000_000) + TimeInterval(ns % 1_000_000_000) / 1e9)
    }

    public static func nanos(_ date: Date) -> UInt64 {
        let t = date.timeIntervalSince1970
        guard t > 0 else { return 0 }
        return UInt64(t * 1_000) * 1_000_000
    }

    /// `yyyy-MM-dd HH:mm:ss.nnnnnnnnn` in the given time zone, keeping full nanosecond precision.
    public static func timestamp(_ ns: UInt64, timeZone: TimeZone = .current) -> String {
        guard ns != 0 else { return "—" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let seconds = Date(timeIntervalSince1970: TimeInterval(ns / 1_000_000_000))
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: seconds)
        let frac = String(ns % 1_000_000_000)
        let pad = String(repeating: "0", count: 9 - frac.count) + frac
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        ) + pad
    }
}
