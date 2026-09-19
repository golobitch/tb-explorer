//! A read-only client for TigerBeetle, over the `tb_client` archive vendored for this repo.
//!
//! Mirrors the Swift `TBKit` next door: same pinned release, same six read operations, same
//! absence of any create path.

pub mod chain;
pub mod client;
pub mod ffi;
pub mod format;
pub mod models;
pub mod queries;
pub mod wire;

pub use chain::{Chain, DEFAULT_LOOKBACK, MAX_LOOKBACK, PendingResolution, PendingStatus};
pub use client::{CLIENT_VERSION, Client, DEFAULT_TIMEOUT, TbError};
pub use ffi::Operation;
pub use format::{AmountStyle, Currency, currency};
pub use models::{
    Account, AccountFilter, Balance, DEFAULT_LIMIT, MAX_LIMIT, QueryFilter, Transfer, clamp_limit,
    next_cursor,
};
pub use queries::Found;
