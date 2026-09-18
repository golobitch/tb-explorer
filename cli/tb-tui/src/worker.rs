//! Queries run on their own thread.
//!
//! `tbclient::Client::submit` blocks until the cluster answers, which is the right shape for a
//! worker and the wrong one for a render loop: a slow reply would freeze the interface and swallow
//! keystrokes. The app sends a `Query` and keeps drawing; the answer arrives as an `Update`.

use std::sync::Arc;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

use tbclient::{Account, AccountFilter, Balance, Client, QueryFilter, TbError, Transfer};

/// Some variants are served by views that land in the next slice; the worker handles them now so
/// the query surface stays in one place.
#[allow(dead_code)]
#[derive(Debug, Clone)]
pub enum Query {
    Accounts { filter: QueryFilter, append: bool },
    Transfers { filter: QueryFilter, append: bool },
    AccountTransfers { filter: AccountFilter, append: bool },
    AccountBalances { filter: AccountFilter },
    Lookup { id: u128 },
    Ping,
}

#[derive(Debug)]
pub enum Update {
    Accounts { rows: Vec<Account>, append: bool },
    Transfers { rows: Vec<Transfer>, append: bool },
    Balances { rows: Vec<Balance> },
    Found(tbclient::Found),
    Latency(std::time::Duration),
    Failed(TbError),
}

pub struct Worker {
    requests: Sender<Query>,
    pub updates: Receiver<Update>,
}

impl Worker {
    pub fn spawn(client: Arc<Client>) -> Self {
        let (requests, inbox) = mpsc::channel::<Query>();
        let (outbox, updates) = mpsc::channel::<Update>();

        thread::spawn(move || {
            // Ends when the app drops its sender, which is how the worker learns to stop.
            for query in inbox {
                let update = run(&client, query);
                if outbox.send(update).is_err() {
                    break;
                }
            }
        });

        Self { requests, updates }
    }

    /// Queues a query. A closed channel means the worker is gone, which only happens on the way
    /// out, so there is nothing useful to report.
    pub fn send(&self, query: Query) {
        let _ = self.requests.send(query);
    }
}

fn run(client: &Client, query: Query) -> Update {
    match query {
        Query::Accounts { filter, append } => match client.query_accounts(&filter) {
            Ok(rows) => Update::Accounts { rows, append },
            Err(error) => Update::Failed(error),
        },
        Query::Transfers { filter, append } => match client.query_transfers(&filter) {
            Ok(rows) => Update::Transfers { rows, append },
            Err(error) => Update::Failed(error),
        },
        Query::AccountTransfers { filter, append } => match client.account_transfers(&filter) {
            Ok(rows) => Update::Transfers { rows, append },
            Err(error) => Update::Failed(error),
        },
        Query::AccountBalances { filter } => match client.account_balances(&filter) {
            Ok(rows) => Update::Balances { rows },
            Err(error) => Update::Failed(error),
        },
        Query::Lookup { id } => match client.lookup_id(id) {
            Ok(found) => Update::Found(found),
            Err(error) => Update::Failed(error),
        },
        Query::Ping => match client.ping() {
            Ok(latency) => Update::Latency(latency),
            Err(error) => Update::Failed(error),
        },
    }
}

#[cfg(test)]
impl Worker {
    /// Channels with no cluster behind them: queries go nowhere and no answer ever arrives, which
    /// is exactly what a rendering test wants.
    pub fn detached() -> Self {
        let (requests, _) = mpsc::channel();
        let (_, updates) = mpsc::channel();
        Self { requests, updates }
    }
}
