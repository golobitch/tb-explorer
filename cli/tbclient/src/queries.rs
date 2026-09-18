//! The six read operations, and the two ways of asking about one account.

use crate::client::{Client, DEFAULT_TIMEOUT, TbError};
use crate::ffi::Operation;
use crate::models::{Account, AccountFilter, Balance, QueryFilter, Transfer};
use crate::wire;

/// What an id turned out to name.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Found {
    Account(Account),
    Transfer(Transfer),
    Nothing,
}

impl Client {
    pub fn lookup_accounts(&self, ids: &[u128]) -> Result<Vec<Account>, TbError> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let reply = self.submit(Operation::LookupAccounts, wire::ids(ids), DEFAULT_TIMEOUT)?;
        wire::accounts(&reply)
    }

    pub fn lookup_transfers(&self, ids: &[u128]) -> Result<Vec<Transfer>, TbError> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }
        let reply = self.submit(Operation::LookupTransfers, wire::ids(ids), DEFAULT_TIMEOUT)?;
        wire::transfers(&reply)
    }

    pub fn account_transfers(&self, filter: &AccountFilter) -> Result<Vec<Transfer>, TbError> {
        let reply = self.submit(
            Operation::GetAccountTransfers,
            wire::account_filter(filter),
            DEFAULT_TIMEOUT,
        )?;
        wire::transfers(&reply)
    }

    /// Only accounts created with the `history` flag have balances to return; for the rest the
    /// cluster answers with nothing, which is not an error.
    pub fn account_balances(&self, filter: &AccountFilter) -> Result<Vec<Balance>, TbError> {
        let reply = self.submit(
            Operation::GetAccountBalances,
            wire::account_filter(filter),
            DEFAULT_TIMEOUT,
        )?;
        wire::balances(&reply)
    }

    pub fn query_accounts(&self, filter: &QueryFilter) -> Result<Vec<Account>, TbError> {
        let reply = self.submit(
            Operation::QueryAccounts,
            wire::query_filter(filter),
            DEFAULT_TIMEOUT,
        )?;
        wire::accounts(&reply)
    }

    pub fn query_transfers(&self, filter: &QueryFilter) -> Result<Vec<Transfer>, TbError> {
        let reply = self.submit(
            Operation::QueryTransfers,
            wire::query_filter(filter),
            DEFAULT_TIMEOUT,
        )?;
        wire::transfers(&reply)
    }

    /// Resolves an id the user typed, which could name either kind. Accounts are asked first
    /// because that is the commoner case, and an id is never both.
    pub fn lookup_id(&self, id: u128) -> Result<Found, TbError> {
        if let Some(account) = self.lookup_accounts(&[id])?.first() {
            return Ok(Found::Account(*account));
        }
        if let Some(transfer) = self.lookup_transfers(&[id])?.first() {
            return Ok(Found::Transfer(*transfer));
        }
        Ok(Found::Nothing)
    }
}
