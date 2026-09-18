import Foundation

extension TBFormat {
    /// Renders an exact u128 amount scaled by a ledger's minor unit, e.g. `123456` with
    /// exponent 2 becomes `1,234.56 $`.
    ///
    /// Entirely string arithmetic: `UInt128.max` is 39 digits, which neither `Double` nor
    /// `Decimal` can hold, so the digits are padded and split rather than divided. Separators are
    /// parameters so callers (and tests) are not at the mercy of the current locale.
    public static func amount(
        _ v: UInt128,
        format: LedgerFormat?,
        grouping: String = Locale.current.groupingSeparator ?? ",",
        decimal: String = Locale.current.decimalSeparator ?? "."
    ) -> String {
        guard let format, format.exponent > 0 || format.unit != nil else {
            return amount(v, separator: grouping)
        }
        let scaled = scale(String(v), exponent: Int(format.exponent), grouping: grouping, decimal: decimal)
        guard let unit = format.unit else { return scaled }
        return scaled + "\u{00A0}" + unit
    }

    public static func amount(
        _ v: SignedAmount,
        format: LedgerFormat?,
        grouping: String = Locale.current.groupingSeparator ?? ",",
        decimal: String = Locale.current.decimalSeparator ?? "."
    ) -> String {
        let body = amount(v.magnitude, format: format, grouping: grouping, decimal: decimal)
        return v.isNegative && v.magnitude != 0 ? "−" + body : body
    }

    /// Inserts a decimal point `exponent` digits from the right, grouping only the integer part.
    static func scale(_ digits: String, exponent: Int, grouping: String, decimal: String) -> String {
        guard exponent > 0 else { return group(digits, separator: grouping) }
        // A value smaller than one unit needs leading zeros: "5" with exponent 2 is "0.05".
        let padded = digits.count > exponent
            ? digits
            : String(repeating: "0", count: exponent - digits.count + 1) + digits
        let split = padded.index(padded.endIndex, offsetBy: -exponent)
        let whole = group(String(padded[padded.startIndex..<split]), separator: grouping)
        return whole + decimal + String(padded[split...])
    }
}
