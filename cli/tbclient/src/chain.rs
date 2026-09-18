//! Pending → post/void resolution, and linked groups.
//!
//! TigerBeetle stores neither relationship as a link you can follow: a post or void names the
//! pending transfer it resolves, and a linked group is contiguous timestamps with a flag. Both are
//! therefore reconstructed by scanning, exactly as `ui/Sources/TBKit/Chain.swift` does.

use std::time::{SystemTime, UNIX_EPOCH};

use crate::client::{Client, TbError};
use crate::models::{AccountFilter, MAX_LIMIT, QueryFilter, Transfer, transfer_flags};

pub const DEFAULT_LOOKBACK: u32 = 1_000;
pub const MAX_LOOKBACK: u32 = 1_000_000;

/// A linked chain never exceeds one batch.
const LINKED_PAGE: u32 = 8_189;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PendingStatus {
    Posted,
    Voided,
    Expired,
    Pending,
    /// Nothing resolved it within the scanned window, and the scan did not reach the account's
    /// newest transfer — so the answer is "not known from here", not "still pending".
    Unknown,
}

impl PendingStatus {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Posted => "posted",
            Self::Voided => "voided",
            Self::Expired => "expired",
            Self::Pending => "pending",
            Self::Unknown => "unresolved in lookback",
        }
    }
}

#[derive(Clone, Debug)]
pub struct PendingResolution {
    pub status: PendingStatus,
    /// Post or void transfers that reference the pending transfer.
    pub resolutions: Vec<Transfer>,
    /// Later debit-account transfers examined.
    pub scanned: u32,
    /// True when the scan reached the newest transfer on the debit account.
    pub exhausted: bool,
    /// Expiry in nanoseconds since the epoch; `None` when the pending never expires.
    pub expires_at: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct Chain {
    pub transfer: Transfer,
    /// The referenced pending transfer, when this one posts or voids.
    pub pending: Option<Transfer>,
    /// Set when this transfer, or the pending it references, is a pending transfer.
    pub resolution: Option<PendingResolution>,
    /// Members of the linked group in timestamp order; empty when the transfer is not linked.
    pub linked: Vec<Transfer>,
}

fn now_nanos() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
}

impl Client {
    pub fn chain(&self, id: u128, lookback: u32) -> Result<Chain, TbError> {
        self.chain_at(id, lookback, now_nanos())
    }

    /// `now` is a parameter so expiry is testable without waiting for a clock.
    pub fn chain_at(&self, id: u128, lookback: u32, now: u64) -> Result<Chain, TbError> {
        let transfer = *self
            .lookup_transfers(&[id])?
            .first()
            .ok_or_else(|| TbError::NotFound(format!("transfer {id}")))?;

        let lookback = lookback.clamp(1, MAX_LOOKBACK);
        let mut chain = Chain {
            transfer,
            pending: None,
            resolution: None,
            linked: Vec::new(),
        };

        let mut pending = (transfer.flags & transfer_flags::PENDING != 0).then_some(transfer);
        if transfer.pending_id != 0
            && let Some(referenced) = self.lookup_transfers(&[transfer.pending_id])?.first()
        {
            chain.pending = Some(*referenced);
            pending = Some(*referenced);
        }
        if let Some(pending) = pending {
            chain.resolution = Some(self.resolve_pending(&pending, lookback, now)?);
        }

        let group = self.linked_group(&transfer)?;
        if group.len() > 1 {
            chain.linked = group;
        }
        Ok(chain)
    }

    /// A post or void debits the same account as its pending transfer and follows it in time, so
    /// the search is a bounded forward scan of that account's debits.
    fn resolve_pending(
        &self,
        pending: &Transfer,
        lookback: u32,
        now: u64,
    ) -> Result<PendingResolution, TbError> {
        let mut out = PendingResolution {
            status: PendingStatus::Unknown,
            resolutions: Vec::new(),
            scanned: 0,
            exhausted: false,
            expires_at: (pending.timeout > 0).then(|| {
                pending
                    .timestamp
                    .wrapping_add(pending.timeout as u64 * 1_000_000_000)
            }),
        };

        let mut cursor = pending.timestamp.wrapping_add(1);
        while out.scanned < lookback {
            let page = (lookback - out.scanned).min(MAX_LIMIT);
            let batch = self.account_transfers(&AccountFilter {
                account_id: pending.debit_account_id,
                debits: true,
                credits: false,
                timestamp_min: cursor,
                limit: page,
                ..Default::default()
            })?;
            out.scanned += batch.len() as u32;
            out.resolutions
                .extend(batch.iter().filter(|t| t.pending_id == pending.id).copied());
            if !out.resolutions.is_empty() {
                break;
            }
            if (batch.len() as u32) < page {
                out.exhausted = true;
                break;
            }
            cursor = batch[batch.len() - 1].timestamp.wrapping_add(1);
        }

        out.status = if out
            .resolutions
            .iter()
            .any(|t| t.flags & transfer_flags::POST_PENDING_TRANSFER != 0)
        {
            PendingStatus::Posted
        } else if out
            .resolutions
            .iter()
            .any(|t| t.flags & transfer_flags::VOID_PENDING_TRANSFER != 0)
        {
            PendingStatus::Voided
        } else if out.expires_at.is_some_and(|expiry| now >= expiry) {
            PendingStatus::Expired
        } else if out.exhausted {
            PendingStatus::Pending
        } else {
            PendingStatus::Unknown
        };
        Ok(out)
    }

    /// Events in one batch get consecutive timestamps, and a linked chain ends at the first event
    /// without the flag. An unfiltered query walks the global timestamp index, so contiguity has
    /// to be checked against every transfer, not just this account's.
    fn linked_group(&self, transfer: &Transfer) -> Result<Vec<Transfer>, TbError> {
        let mut group = vec![*transfer];

        if transfer.timestamp > 1 {
            let before = self.query_transfers(&QueryFilter {
                timestamp_min: 1,
                timestamp_max: transfer.timestamp - 1,
                limit: LINKED_PAGE,
                reversed: true,
                ..Default::default()
            })?;
            let mut expect = transfer.timestamp - 1;
            for candidate in before {
                if candidate.timestamp != expect || candidate.flags & transfer_flags::LINKED == 0 {
                    break;
                }
                group.push(candidate);
                expect -= 1;
            }
        }

        if transfer.flags & transfer_flags::LINKED != 0 {
            let after = self.query_transfers(&QueryFilter {
                timestamp_min: transfer.timestamp + 1,
                limit: LINKED_PAGE,
                ..Default::default()
            })?;
            let mut expect = transfer.timestamp + 1;
            for candidate in after {
                if candidate.timestamp != expect {
                    break;
                }
                group.push(candidate);
                if candidate.flags & transfer_flags::LINKED == 0 {
                    break;
                }
                expect += 1;
            }
        }

        group.sort_by_key(|t| t.timestamp);
        Ok(group)
    }
}
