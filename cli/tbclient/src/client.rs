use std::ffi::c_void;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use crate::ffi::{
    self, ClientStatus, Completion, InitStatus, Operation, PacketStatus, TbClient, TbPacket,
};

/// The client release this crate speaks, and the version of `Vendor/tigerbeetle`.
pub const CLIENT_VERSION: &str = "0.17.9";

pub const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TbError {
    Init(InitStatus),
    Packet(PacketStatus),
    /// The cluster evicted this client because its release is too old or too new for the replicas.
    VersionMismatch(PacketStatus),
    Timeout(Duration),
    Closed,
    Decode(String),
    NotFound(String),
    Message(String),
}

impl std::fmt::Display for TbError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Init(status) => write!(f, "could not create the client ({status:?})"),
            Self::Packet(status) => write!(f, "the cluster rejected the request ({status:?})"),
            Self::VersionMismatch(status) => write!(
                f,
                "this client speaks TigerBeetle {CLIENT_VERSION}, which the cluster refused ({status:?})"
            ),
            Self::Timeout(after) => write!(f, "no answer within {:.1}s", after.as_secs_f64()),
            Self::Closed => write!(f, "the client is closed"),
            Self::Decode(what) => write!(f, "could not read the reply: {what}"),
            Self::NotFound(what) => write!(f, "{what} not found"),
            Self::Message(text) => write!(f, "{text}"),
        }
    }
}

impl std::error::Error for TbError {}

/// Where a completed request leaves its answer.
type Slot = Arc<(Mutex<Option<Result<Vec<u8>, TbError>>>, Condvar)>;

/// One in-flight request: the packet the cluster holds a pointer to, the payload it points at, and
/// the slot the caller is waiting on.
///
/// Leaked into `packet.user_data` for the duration and reclaimed by the callback, so the packet
/// keeps the stable address `tb_client.h` requires even if the caller has given up waiting.
struct Request {
    packet: TbPacket,
    _payload: Vec<u8>,
    slot: Slot,
}

/// A read-only connection to one cluster.
///
/// Thread-safe: `tb_client` serialises internally, and every request owns its own packet.
pub struct Client {
    handle: *mut TbClient,
}

// SAFETY: tb_client is documented as thread-safe, and nothing in this struct is mutated from Rust
// after `connect` returns — `submit` only passes the handle back to the C client.
unsafe impl Send for Client {}
// SAFETY: as above; concurrent `submit` calls each own their packet and the client serialises.
unsafe impl Sync for Client {}

impl Client {
    pub fn connect(cluster_id: u128, addresses: &str) -> Result<Self, TbError> {
        let handle = Box::into_raw(Box::new(TbClient { opaque: [0; 4] }));
        let cluster = cluster_id.to_le_bytes();
        let address_bytes = addresses.as_bytes();

        // SAFETY: `handle` is a fresh allocation with a stable address, `cluster` is the 16 bytes
        // the header asks for, and the address string outlives the call.
        let status = unsafe {
            ffi::tb_client_init(
                handle,
                cluster.as_ptr(),
                address_bytes.as_ptr().cast(),
                address_bytes.len() as u32,
                COMPLETION_CONTEXT,
                on_completion as Completion,
            )
        };

        if status != InitStatus::Success {
            // SAFETY: init failed, so the client never took ownership of the allocation.
            drop(unsafe { Box::from_raw(handle) });
            return Err(TbError::Init(status));
        }
        Ok(Self { handle })
    }

    /// Submits one request and waits for the cluster's answer.
    ///
    /// Blocking on purpose: the terminal front end runs queries on a worker thread and keeps the
    /// render loop free, which is simpler to reason about than an async runtime for six operations.
    pub fn submit(
        &self,
        operation: Operation,
        payload: Vec<u8>,
        timeout: Duration,
    ) -> Result<Vec<u8>, TbError> {
        let slot: Slot = Arc::new((Mutex::new(None), Condvar::new()));
        let mut request = Box::new(Request {
            packet: TbPacket {
                user_data: std::ptr::null_mut(),
                data: std::ptr::null_mut(),
                data_size: payload.len() as u32,
                user_tag: 0,
                operation: operation as u8,
                status: 0,
                opaque: [0; 64],
            },
            _payload: payload,
            slot: Arc::clone(&slot),
        });

        request.packet.data = request._payload.as_ptr() as *mut c_void;
        let raw = Box::into_raw(request);
        // SAFETY: `raw` is a live allocation; the callback is the only other reader and it runs
        // once, after submission.
        unsafe { (*raw).packet.user_data = raw.cast() };

        // SAFETY: the packet lives inside the leaked request, so its address stays valid until the
        // callback reclaims it.
        let status = unsafe { ffi::tb_client_submit(self.handle, &raw mut (*raw).packet) };
        if status != ClientStatus::Ok {
            // The client never took the packet, so nothing else will free it.
            // SAFETY: submission failed, so no callback will fire for `raw`.
            drop(unsafe { Box::from_raw(raw) });
            return Err(TbError::Closed);
        }

        let (lock, cvar) = &*slot;
        let mut answer = lock.lock().unwrap();
        while answer.is_none() {
            let (next, wait) = cvar.wait_timeout(answer, timeout).unwrap();
            answer = next;
            if wait.timed_out() && answer.is_none() {
                // The request stays alive and owned by the in-flight packet; the callback will
                // still run and free it, writing into a slot nobody reads.
                return Err(TbError::Timeout(timeout));
            }
        }
        answer.take().unwrap()
    }

    /// One round trip, timed: looks up the zero id, which no account can have, so the cluster
    /// answers with an empty result and the reply measures the path rather than the data.
    pub fn ping(&self) -> Result<Duration, TbError> {
        let start = Instant::now();
        self.submit(
            Operation::LookupAccounts,
            0u128.to_le_bytes().to_vec(),
            DEFAULT_TIMEOUT,
        )?;
        Ok(start.elapsed())
    }
}

impl Drop for Client {
    fn drop(&mut self) {
        // SAFETY: `handle` was created by `connect` and is dropped once.
        unsafe {
            ffi::tb_client_deinit(self.handle);
            drop(Box::from_raw(self.handle));
        }
    }
}

/// Matches the official clients: unused, and distinctive enough to spot in a log.
const COMPLETION_CONTEXT: usize = 0xAB;

/// Runs on tb_client's thread. Copies the result out, wakes the waiter, and does nothing else —
/// the header is explicit that `result` dies with this call, and the blog post is explicit that
/// blocking here blocks the client.
unsafe extern "C" fn on_completion(
    _userdata: usize,
    packet: *mut TbPacket,
    _timestamp: u64,
    result: *const u8,
    result_size: u32,
) {
    if packet.is_null() {
        return;
    }
    // SAFETY: the packet is the one submitted, and its `user_data` is the request we leaked.
    let raw = unsafe { (*packet).user_data } as *mut Request;
    if raw.is_null() {
        return;
    }
    // SAFETY: the callback fires once per packet, so this reclaims the allocation exactly once.
    let request = unsafe { Box::from_raw(raw) };

    let status = PacketStatus::from_raw(request.packet.status);
    let answer = match status {
        PacketStatus::Ok => {
            let bytes = if result.is_null() || result_size == 0 {
                Vec::new()
            } else {
                // SAFETY: the header guarantees `result_size` bytes are readable for this call.
                unsafe { std::slice::from_raw_parts(result, result_size as usize) }.to_vec()
            };
            Ok(bytes)
        }
        PacketStatus::ClientReleaseTooLow | PacketStatus::ClientReleaseTooHigh => {
            Err(TbError::VersionMismatch(status))
        }
        PacketStatus::ClientShutdown => Err(TbError::Closed),
        other => Err(TbError::Packet(other)),
    };

    let (lock, cvar) = &*request.slot;
    if let Ok(mut held) = lock.lock() {
        *held = Some(answer);
        cvar.notify_all();
    }
}
