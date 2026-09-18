//! A read-only client for TigerBeetle, over the `tb_client` archive vendored for this repo.
//!
//! Mirrors the Swift `TBKit` next door: same pinned release, same six read operations, same
//! absence of any create path.

pub mod client;
pub mod ffi;

pub use client::{CLIENT_VERSION, Client, DEFAULT_TIMEOUT, TbError};
pub use ffi::Operation;
