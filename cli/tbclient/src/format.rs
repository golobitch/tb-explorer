//! Making amounts readable without making them wrong.
//!
//! A TigerBeetle amount is a `u128` — up to 39 digits, which neither `f64` nor any fixed-point
//! type can hold. Everything here is therefore string arithmetic: digits are padded and split,
//! never divided. Ported from `ui/Sources/TBKit/{U128,AmountFormat,ISO4217}.swift`, so both front
//! ends render the same number the same way.

/// A currency from the ISO 4217 list.
///
/// `exponent` is the minor unit: digits after the decimal point, 2 for USD, 0 for JPY, 3 for BHD.
/// It is what turns an integer into an amount.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Currency {
    pub numeric: u32,
    pub alpha: &'static str,
    pub exponent: u8,
    /// Only the widely recognised ones; elsewhere the alpha code reads better than a glyph.
    pub symbol: Option<&'static str>,
}

impl Currency {
    /// What follows the digits: the symbol where there is one, the code otherwise.
    pub fn unit(&self) -> &'static str {
        self.symbol.unwrap_or(self.alpha)
    }
}

/// Maps a ledger id to a currency, assuming the ledger uses ISO 4217 numeric codes.
///
/// A convention, not a rule — a ledger id is just a `u32`. Treat a match as a default the reader
/// can switch off, never as a statement of fact.
pub fn currency(ledger: u32) -> Option<Currency> {
    CURRENCIES
        .iter()
        .find(|c| c.0 == ledger)
        .map(|&(numeric, alpha, exponent, symbol)| Currency {
            numeric,
            alpha,
            exponent,
            symbol,
        })
}

/// Groups digits in threes with a thin space, which reads in a terminal without looking like a
/// decimal point to someone whose locale uses `.` as a separator.
pub fn group(digits: &str, separator: &str) -> String {
    let (sign, rest) = match digits.strip_prefix('-') {
        Some(rest) => ("-", rest),
        None => ("", digits),
    };
    let mut out = String::with_capacity(rest.len() + rest.len() / 3 + 1);
    for (i, c) in rest.chars().enumerate() {
        if i > 0 && (rest.len() - i) % 3 == 0 {
            out.push_str(separator);
        }
        out.push(c);
    }
    format!("{sign}{out}")
}

/// Inserts a decimal point `exponent` digits from the right, grouping only the integer part.
pub fn scale(digits: &str, exponent: u8, separator: &str, decimal: &str) -> String {
    if exponent == 0 {
        return group(digits, separator);
    }
    let exponent = exponent as usize;
    // A value smaller than one unit needs leading zeros: "5" with exponent 2 is "0.05".
    let padded = if digits.len() > exponent {
        digits.to_string()
    } else {
        format!("{}{digits}", "0".repeat(exponent - digits.len() + 1))
    };
    let split = padded.len() - exponent;
    format!(
        "{}{decimal}{}",
        group(&padded[..split], separator),
        &padded[split..]
    )
}

/// How amounts are rendered on screen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct AmountStyle {
    /// Read the ledger id as an ISO 4217 code and scale by its minor unit.
    pub currency: bool,
    pub separator: &'static str,
    pub decimal: &'static str,
}

impl Default for AmountStyle {
    fn default() -> Self {
        Self {
            currency: false,
            // A thin space groups without colliding with either decimal convention.
            separator: "\u{202F}",
            decimal: ".",
        }
    }
}

impl AmountStyle {
    /// An exact amount, grouped, and scaled into its currency when asked and when the ledger has
    /// one. Anything else stays the integer TigerBeetle stores.
    pub fn amount(&self, value: u128, ledger: u32) -> String {
        match self.currency.then(|| currency(ledger)).flatten() {
            Some(currency) => format!(
                "{} {}",
                scale(
                    &value.to_string(),
                    currency.exponent,
                    self.separator,
                    self.decimal
                ),
                currency.unit()
            ),
            None => group(&value.to_string(), self.separator),
        }
    }

    /// The same, for a value that can be negative — a net is the difference of two u128 values, so
    /// it arrives as a magnitude and a sign rather than as one signed integer.
    pub fn signed(&self, magnitude: u128, negative: bool, ledger: u32) -> String {
        let body = self.amount(magnitude, ledger);
        if negative && magnitude != 0 {
            format!("-{body}")
        } else {
            body
        }
    }

    /// `840 · USD` when the ledger names a currency and currency mode is on, `840` otherwise.
    pub fn ledger(&self, ledger: u32) -> String {
        match self.currency.then(|| currency(ledger)).flatten() {
            Some(currency) => format!("{ledger} · {}", currency.alpha),
            None => ledger.to_string(),
        }
    }
}

/// Active ISO 4217 codes: numeric, alpha, minor units, and a symbol for the familiar ones.
/// Withdrawn codes are omitted, so a ledger numbered after a retired currency has no match.
#[rustfmt::skip]
const CURRENCIES: &[(u32, &str, u8, Option<&str>)] = &[
    (8, "ALL", 2, None), (12, "DZD", 2, None), (32, "ARS", 2, None), (36, "AUD", 2, Some("A$")),
    (44, "BSD", 2, None), (48, "BHD", 3, None), (50, "BDT", 2, None), (51, "AMD", 2, None),
    (52, "BBD", 2, None), (60, "BMD", 2, None), (64, "BTN", 2, None), (68, "BOB", 2, None),
    (72, "BWP", 2, None), (84, "BZD", 2, None), (90, "SBD", 2, None), (96, "BND", 2, None),
    (104, "MMK", 2, None), (108, "BIF", 0, None), (116, "KHR", 2, None), (124, "CAD", 2, Some("C$")),
    (132, "CVE", 2, None), (136, "KYD", 2, None), (144, "LKR", 2, None), (152, "CLP", 0, None),
    (156, "CNY", 2, Some("¥")), (170, "COP", 2, None), (174, "KMF", 0, None), (188, "CRC", 2, None),
    (191, "HRK", 2, None), (192, "CUP", 2, None), (203, "CZK", 2, None), (208, "DKK", 2, None),
    (214, "DOP", 2, None), (222, "SVC", 2, None), (230, "ETB", 2, None), (232, "ERN", 2, None),
    (238, "FKP", 2, None), (242, "FJD", 2, None), (262, "DJF", 0, None), (270, "GMD", 2, None),
    (292, "GIP", 2, None), (320, "GTQ", 2, None), (324, "GNF", 0, None), (328, "GYD", 2, None),
    (332, "HTG", 2, None), (340, "HNL", 2, None), (344, "HKD", 2, Some("HK$")), (348, "HUF", 2, None),
    (352, "ISK", 0, None), (356, "INR", 2, Some("₹")), (360, "IDR", 2, None), (364, "IRR", 2, None),
    (368, "IQD", 3, None), (376, "ILS", 2, Some("₪")), (388, "JMD", 2, None), (392, "JPY", 0, Some("¥")),
    (398, "KZT", 2, None), (400, "JOD", 3, None), (404, "KES", 2, None), (408, "KPW", 2, None),
    (410, "KRW", 0, Some("₩")), (414, "KWD", 3, None), (417, "KGS", 2, None), (418, "LAK", 2, None),
    (422, "LBP", 2, None), (426, "LSL", 2, None), (430, "LRD", 2, None), (434, "LYD", 3, None),
    (446, "MOP", 2, None), (454, "MWK", 2, None), (458, "MYR", 2, None), (462, "MVR", 2, None),
    (480, "MUR", 2, None), (484, "MXN", 2, None), (496, "MNT", 2, None), (498, "MDL", 2, None),
    (504, "MAD", 2, None), (512, "OMR", 3, None), (516, "NAD", 2, None), (524, "NPR", 2, None),
    (532, "ANG", 2, None), (533, "AWG", 2, None), (548, "VUV", 0, None), (554, "NZD", 2, Some("NZ$")),
    (558, "NIO", 2, None), (566, "NGN", 2, None), (578, "NOK", 2, None), (586, "PKR", 2, None),
    (590, "PAB", 2, None), (598, "PGK", 2, None), (600, "PYG", 0, None), (604, "PEN", 2, None),
    (608, "PHP", 2, Some("₱")), (634, "QAR", 2, None), (643, "RUB", 2, Some("₽")), (646, "RWF", 0, None),
    (654, "SHP", 2, None), (682, "SAR", 2, None), (690, "SCR", 2, None), (694, "SLL", 2, None),
    (702, "SGD", 2, Some("S$")), (704, "VND", 0, Some("₫")), (706, "SOS", 2, None), (710, "ZAR", 2, Some("R")),
    (728, "SSP", 2, None), (748, "SZL", 2, None), (752, "SEK", 2, None), (756, "CHF", 2, None),
    (760, "SYP", 2, None), (764, "THB", 2, Some("฿")), (776, "TOP", 2, None), (780, "TTD", 2, None),
    (784, "AED", 2, None), (788, "TND", 3, None), (800, "UGX", 0, None), (807, "MKD", 2, None),
    (818, "EGP", 2, None), (826, "GBP", 2, Some("£")), (834, "TZS", 2, None), (840, "USD", 2, Some("$")),
    (858, "UYU", 2, None), (860, "UZS", 2, None), (882, "WST", 2, None), (886, "YER", 2, None),
    (901, "TWD", 2, Some("NT$")), (925, "SLE", 2, None), (926, "VED", 2, None), (927, "UYW", 4, None),
    (928, "VES", 2, None), (929, "MRU", 2, None), (930, "STN", 2, None), (932, "ZWL", 2, None),
    (933, "BYN", 2, None), (934, "TMT", 2, None), (936, "GHS", 2, None), (938, "SDG", 2, None),
    (940, "UYI", 0, None), (941, "RSD", 2, None), (943, "MZN", 2, None), (944, "AZN", 2, None),
    (946, "RON", 2, None), (947, "CHE", 2, None), (948, "CHW", 2, None), (949, "TRY", 2, Some("₺")),
    (950, "XAF", 0, None), (951, "XCD", 2, None), (952, "XOF", 0, None), (953, "XPF", 0, None),
    (967, "ZMW", 2, None), (968, "SRD", 2, None), (969, "MGA", 2, None), (970, "COU", 2, None),
    (971, "AFN", 2, None), (972, "TJS", 2, None), (973, "AOA", 2, None), (975, "BGN", 2, None),
    (976, "CDF", 2, None), (977, "BAM", 2, None), (978, "EUR", 2, Some("€")), (979, "MXV", 2, None),
    (980, "UAH", 2, Some("₴")), (981, "GEL", 2, None), (984, "BOV", 2, None), (985, "PLN", 2, Some("zł")),
    (986, "BRL", 2, Some("R$")), (990, "CLF", 4, None), (994, "XSU", 0, None), (997, "USN", 2, None),
];

#[cfg(test)]
mod tests {
    use super::*;

    /// Fixed separators keep these independent of anyone's locale, as the Swift suite does.
    fn style(currency: bool) -> AmountStyle {
        AmountStyle {
            currency,
            separator: ",",
            decimal: ".",
        }
    }

    #[test]
    fn groups_digits_in_threes() {
        assert_eq!(group("1", ","), "1");
        assert_eq!(group("123", ","), "123");
        assert_eq!(group("1234", ","), "1,234");
        assert_eq!(group("1063827", ","), "1,063,827");
        assert_eq!(group("-1063827", ","), "-1,063,827");
        assert_eq!(group("", ","), "");
    }

    #[test]
    fn scales_by_the_minor_unit() {
        assert_eq!(scale("123456", 2, ",", "."), "1,234.56");
        assert_eq!(scale("123456", 0, ",", "."), "123,456");
        assert_eq!(scale("123456", 3, ",", "."), "123.456");
    }

    #[test]
    fn a_value_smaller_than_one_unit_keeps_its_leading_zero() {
        assert_eq!(scale("5", 2, ",", "."), "0.05");
        assert_eq!(scale("0", 2, ",", "."), "0.00");
        assert_eq!(scale("50", 2, ",", "."), "0.50");
    }

    #[test]
    fn the_largest_amount_survives_the_largest_exponent() {
        let max = u128::MAX.to_string();
        assert_eq!(max.len(), 39);
        let scaled = scale(&max, 38, "", ".");
        // One digit, the point, then the other 38 — nothing rounded away.
        assert_eq!(scaled.len(), 40);
        assert!(scaled.starts_with("3."));
        assert!(scaled.ends_with(&max[1..]));
    }

    #[test]
    fn currency_mode_reads_the_ledger_as_iso_4217() {
        let style = style(true);
        assert_eq!(style.amount(1_063_827, 840), "10,638.27 $");
        assert_eq!(
            style.amount(1_063_827, 392),
            "1,063,827 ¥",
            "JPY has no minor unit"
        );
        assert_eq!(
            style.amount(1_063_827, 48),
            "1,063.827 BHD",
            "BHD has three"
        );
        assert_eq!(style.ledger(840), "840 · USD");
    }

    #[test]
    fn a_ledger_that_is_not_a_currency_stays_an_integer() {
        let style = style(true);
        // 700 is unassigned in ISO 4217, whatever the seed calls it.
        assert_eq!(currency(700), None);
        assert_eq!(style.amount(1_063_827, 700), "1,063,827");
        assert_eq!(style.ledger(700), "700");
    }

    #[test]
    fn currency_mode_off_never_scales() {
        let style = style(false);
        assert_eq!(style.amount(1_063_827, 840), "1,063,827");
        assert_eq!(style.ledger(840), "840");
    }

    #[test]
    fn a_net_keeps_its_sign_and_zero_never_gets_one() {
        let style = style(true);
        assert_eq!(style.signed(29_885, true, 840), "-298.85 $");
        assert_eq!(style.signed(29_885, false, 840), "298.85 $");
        assert_eq!(style.signed(0, true, 840), "0.00 $");
    }

    #[test]
    fn the_table_holds_the_currencies_that_make_naive_rounding_wrong() {
        assert_eq!(currency(840).unwrap().exponent, 2);
        assert_eq!(currency(392).unwrap().exponent, 0, "JPY");
        assert_eq!(currency(410).unwrap().exponent, 0, "KRW");
        assert_eq!(currency(48).unwrap().exponent, 3, "BHD");
        assert_eq!(currency(414).unwrap().exponent, 3, "KWD");
        assert_eq!(currency(990).unwrap().exponent, 4, "CLF");
        assert_eq!(currency(978).unwrap().unit(), "€");
        assert_eq!(
            currency(970).unwrap().unit(),
            "COU",
            "no symbol, so the code"
        );
    }
}
