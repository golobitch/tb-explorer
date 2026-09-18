//! Declarations for the parts of `tb_client.h` this crate uses.
//!
//! Hand-written rather than generated: the surface is seven functions and four enums, and the read
//! operations are the point. The two write operations the header declares at 146 and 147 are
//! deliberately absent, so no amount of calling into this module can change a cluster.

use std::ffi::{c_char, c_void};

/// "must be pinned (not copyable or movable), address must remain stable" — `tb_client.h`.
#[repr(C)]
pub struct TbClient {
    pub opaque: [u64; 4],
}

#[repr(C)]
pub struct TbPacket {
    pub user_data: *mut c_void,
    pub data: *mut c_void,
    pub data_size: u32,
    pub user_tag: u16,
    pub operation: u8,
    pub status: u8,
    pub opaque: [u8; 64],
}

/// The read half of `TB_OPERATION`. The two write operations exist in the header at 146 and 147
/// and are left out here on purpose.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum Operation {
    LookupAccounts = 140,
    LookupTransfers = 141,
    GetAccountTransfers = 142,
    GetAccountBalances = 143,
    QueryAccounts = 144,
    QueryTransfers = 145,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum PacketStatus {
    Ok = 0,
    TooMuchData = 1,
    ClientEvicted = 2,
    ClientReleaseTooLow = 3,
    ClientReleaseTooHigh = 4,
    ClientShutdown = 5,
    InvalidOperation = 6,
    InvalidDataSize = 7,
}

impl PacketStatus {
    pub fn from_raw(raw: u8) -> Self {
        match raw {
            0 => Self::Ok,
            1 => Self::TooMuchData,
            2 => Self::ClientEvicted,
            3 => Self::ClientReleaseTooLow,
            4 => Self::ClientReleaseTooHigh,
            5 => Self::ClientShutdown,
            6 => Self::InvalidOperation,
            _ => Self::InvalidDataSize,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum InitStatus {
    Success = 0,
    Unexpected = 1,
    OutOfMemory = 2,
    AddressInvalid = 3,
    AddressLimitExceeded = 4,
    SystemResources = 5,
    NetworkSubsystem = 6,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u32)]
pub enum ClientStatus {
    Ok = 0,
    Invalid = 1,
}

/// Invoked **on tb_client's own thread**, with `result` valid only for the call itself.
pub type Completion = unsafe extern "C" fn(
    userdata: usize,
    packet: *mut TbPacket,
    timestamp: u64,
    result: *const u8,
    result_size: u32,
);

unsafe extern "C" {
    pub fn tb_client_init(
        client_out: *mut TbClient,
        cluster_id: *const u8,
        address_ptr: *const c_char,
        address_len: u32,
        completion_ctx: usize,
        completion_callback: Completion,
    ) -> InitStatus;

    pub fn tb_client_submit(client: *mut TbClient, packet: *mut TbPacket) -> ClientStatus;

    pub fn tb_client_deinit(client: *mut TbClient) -> ClientStatus;
}
