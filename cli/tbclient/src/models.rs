//! TigerBeetle's structs, laid out exactly as `tb_client.h` declares them.
//!
//! Rust has native `u128`, so these are `#[repr(C)]` structs read straight from the reply rather
//! than the byte-by-byte decoding the Swift client needs. The layout is asserted in `wire.rs`
//! tests against the same offsets `ui/Tests/TBKitTests/WireTests.swift` pins.

pub const ACCOUNT_SIZE: usize = 128;
pub const TRANSFER_SIZE: usize = 128;
pub const BALANCE_SIZE: usize = 128;
pub const ACCOUNT_FILTER_SIZE: usize = 128;
pub const QUERY_FILTER_SIZE: usize = 64;
pub const ID_SIZE: usize = 16;

/// Maximum events per request; stays below what a single TigerBeetle reply can carry.
pub const MAX_LIMIT: u32 = 8000;
pub const DEFAULT_LIMIT: u32 = 100;

/// `0` means "unset, use the default"; anything above the cap is clamped to it.
pub fn clamp_limit(limit: u32) -> u32 {
    if limit == 0 {
        DEFAULT_LIMIT
    } else {
        limit.min(MAX_LIMIT)
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(C)]
pub struct Account {
    pub id: u128,
    pub debits_pending: u128,
    pub debits_posted: u128,
    pub credits_pending: u128,
    pub credits_posted: u128,
    pub user_data_128: u128,
    pub user_data_64: u64,
    pub user_data_32: u32,
    pub reserved: u32,
    pub ledger: u32,
    pub code: u16,
    pub flags: u16,
    pub timestamp: u64,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(C)]
pub struct Transfer {
    pub id: u128,
    pub debit_account_id: u128,
    pub credit_account_id: u128,
    pub amount: u128,
    pub pending_id: u128,
    pub user_data_128: u128,
    pub user_data_64: u64,
    pub user_data_32: u32,
    pub timeout: u32,
    pub ledger: u32,
    pub code: u16,
    pub flags: u16,
    pub timestamp: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(C)]
pub struct Balance {
    pub debits_pending: u128,
    pub debits_posted: u128,
    pub credits_pending: u128,
    pub credits_posted: u128,
    pub timestamp: u64,
    pub reserved: [u8; 56],
}

pub mod account_flags {
    pub const LINKED: u16 = 1 << 0;
    pub const DEBITS_MUST_NOT_EXCEED_CREDITS: u16 = 1 << 1;
    pub const CREDITS_MUST_NOT_EXCEED_DEBITS: u16 = 1 << 2;
    pub const HISTORY: u16 = 1 << 3;
    pub const IMPORTED: u16 = 1 << 4;
    pub const CLOSED: u16 = 1 << 5;

    pub const NAMES: [&str; 6] = [
        "linked",
        "debits_must_not_exceed_credits",
        "credits_must_not_exceed_debits",
        "history",
        "imported",
        "closed",
    ];
}

pub mod transfer_flags {
    pub const LINKED: u16 = 1 << 0;
    pub const PENDING: u16 = 1 << 1;
    pub const POST_PENDING_TRANSFER: u16 = 1 << 2;
    pub const VOID_PENDING_TRANSFER: u16 = 1 << 3;
    pub const BALANCING_DEBIT: u16 = 1 << 4;
    pub const BALANCING_CREDIT: u16 = 1 << 5;
    pub const CLOSING_DEBIT: u16 = 1 << 6;
    pub const CLOSING_CREDIT: u16 = 1 << 7;
    pub const IMPORTED: u16 = 1 << 8;

    pub const NAMES: [&str; 9] = [
        "linked",
        "pending",
        "post_pending_transfer",
        "void_pending_transfer",
        "balancing_debit",
        "balancing_credit",
        "closing_debit",
        "closing_credit",
        "imported",
    ];
}

/// Decoded flag names in bit order; unknown bits render as `unknown_bit_N`.
pub fn flag_names(raw: u16, names: &[&str]) -> Vec<String> {
    (0..16)
        .filter(|bit| raw & (1 << bit) != 0)
        .map(|bit| {
            names
                .get(bit as usize)
                .map(|name| (*name).to_string())
                .unwrap_or_else(|| format!("unknown_bit_{bit}"))
        })
        .collect()
}

impl Account {
    pub fn flag_names(&self) -> Vec<String> {
        flag_names(self.flags, &account_flags::NAMES)
    }

    /// Credits minus debits, as a magnitude and a sign: the difference of two u128 values does not
    /// fit in an i128.
    pub fn net_posted(&self) -> (u128, bool) {
        if self.credits_posted >= self.debits_posted {
            (self.credits_posted - self.debits_posted, false)
        } else {
            (self.debits_posted - self.credits_posted, true)
        }
    }
}

impl Transfer {
    pub fn flag_names(&self) -> Vec<String> {
        flag_names(self.flags, &transfer_flags::NAMES)
    }
}

impl Default for Balance {
    fn default() -> Self {
        // [u8; 56] has no Default; the reserved bytes are zero on the wire anyway.
        Self {
            debits_pending: 0,
            debits_posted: 0,
            credits_pending: 0,
            credits_posted: 0,
            timestamp: 0,
            reserved: [0; 56],
        }
    }
}

impl Balance {
    pub fn net_posted(&self) -> (u128, bool) {
        if self.credits_posted >= self.debits_posted {
            (self.credits_posted - self.debits_posted, false)
        } else {
            (self.debits_posted - self.credits_posted, true)
        }
    }
}

/// Filter for `get_account_transfers` / `get_account_balances`. Zero values mean "any".
#[derive(Clone, Copy, Debug)]
pub struct AccountFilter {
    pub account_id: u128,
    pub user_data_128: u128,
    pub user_data_64: u64,
    pub user_data_32: u32,
    pub code: u16,
    pub timestamp_min: u64,
    pub timestamp_max: u64,
    pub limit: u32,
    pub debits: bool,
    pub credits: bool,
    pub reversed: bool,
}

impl Default for AccountFilter {
    fn default() -> Self {
        Self {
            account_id: 0,
            user_data_128: 0,
            user_data_64: 0,
            user_data_32: 0,
            code: 0,
            timestamp_min: 0,
            timestamp_max: 0,
            limit: DEFAULT_LIMIT,
            debits: true,
            credits: true,
            reversed: false,
        }
    }
}

/// Filter for `query_accounts` / `query_transfers`. Zero values mean "any".
#[derive(Clone, Copy, Debug)]
pub struct QueryFilter {
    pub user_data_128: u128,
    pub user_data_64: u64,
    pub user_data_32: u32,
    pub ledger: u32,
    pub code: u16,
    pub timestamp_min: u64,
    pub timestamp_max: u64,
    pub limit: u32,
    pub reversed: bool,
}

impl Default for QueryFilter {
    fn default() -> Self {
        Self {
            user_data_128: 0,
            user_data_64: 0,
            user_data_32: 0,
            ledger: 0,
            code: 0,
            timestamp_min: 0,
            timestamp_max: 0,
            limit: DEFAULT_LIMIT,
            reversed: false,
        }
    }
}

/// Where the next page starts, given the last row of this one.
///
/// TigerBeetle pages by timestamp, and the bounds are inclusive, so the cursor steps one
/// nanosecond past the row already seen. Same rule as `Cursor.next` in the Swift client.
pub fn next_cursor(after: u64, reversed: bool) -> (u64, u64) {
    if reversed {
        (0, after.saturating_sub(1))
    } else {
        (after.saturating_add(1), 0)
    }
}
