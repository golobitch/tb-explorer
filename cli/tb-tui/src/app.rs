//! What is on screen, and what the keys do to it.

use std::time::{Duration, Instant};

use tbclient::{Account, Balance, QueryFilter, TbError, Transfer};

use crate::worker::{Query, Update, Worker};

/// One screen. The stack of these is what `esc` walks back up.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum View {
    Accounts,
    Transfers,
    Ledgers,
}

impl View {
    pub fn title(&self) -> &'static str {
        match self {
            Self::Accounts => "accounts",
            Self::Transfers => "transfers",
            Self::Ledgers => "ledgers",
        }
    }

    /// The operation behind the view, shown in the header the way the macOS app shows it.
    pub fn operation(&self) -> &'static str {
        match self {
            Self::Accounts => "query_accounts",
            Self::Transfers => "query_transfers",
            Self::Ledgers => "collected while browsing",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    Normal,
    Help,
}

/// The rows behind the current view.
#[derive(Debug, Default)]
pub enum Rows {
    #[default]
    None,
    Accounts(Vec<Account>),
    Transfers(Vec<Transfer>),
    Balances(Vec<Balance>),
    Ledgers(Vec<u32>),
}

impl Rows {
    pub fn len(&self) -> usize {
        match self {
            Self::None => 0,
            Self::Accounts(rows) => rows.len(),
            Self::Transfers(rows) => rows.len(),
            Self::Balances(rows) => rows.len(),
            Self::Ledgers(rows) => rows.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

pub struct App {
    pub cluster_id: u128,
    pub addresses: String,
    pub latency: Option<Duration>,
    pub view: View,
    pub rows: Rows,
    pub selected: usize,
    pub mode: Mode,
    pub status: Option<String>,
    pub error: Option<String>,
    pub loading: bool,
    /// Ledgers are not enumerable in TigerBeetle, so they are collected from what has been seen —
    /// the same approach the macOS app takes.
    pub ledgers: Vec<u32>,
    pub newest_first: bool,
    pub quit: bool,
    worker: Worker,
    last_refresh: Instant,
}

impl App {
    pub fn new(cluster_id: u128, addresses: String, worker: Worker) -> Self {
        let mut app = Self {
            cluster_id,
            addresses,
            latency: None,
            view: View::Accounts,
            rows: Rows::None,
            selected: 0,
            mode: Mode::Normal,
            status: None,
            error: None,
            loading: false,
            ledgers: Vec::new(),
            newest_first: false,
            quit: false,
            worker,
            last_refresh: Instant::now(),
        };
        app.reload();
        app.worker.send(Query::Ping);
        app
    }

    pub fn filter(&self) -> QueryFilter {
        QueryFilter {
            limit: 200,
            reversed: self.newest_first,
            ..Default::default()
        }
    }

    pub fn reload(&mut self) {
        self.loading = true;
        self.error = None;
        self.last_refresh = Instant::now();
        match self.view {
            View::Accounts => self.worker.send(Query::Accounts {
                filter: self.filter(),
                append: false,
            }),
            View::Transfers => self.worker.send(Query::Transfers {
                filter: self.filter(),
                append: false,
            }),
            View::Ledgers => {
                self.rows = Rows::Ledgers(self.ledgers.clone());
                self.loading = false;
            }
        }
    }

    pub fn show(&mut self, view: View) {
        if self.view != view {
            self.view = view;
            self.selected = 0;
            self.rows = Rows::None;
            self.reload();
        }
    }

    /// Everything that arrived since the last frame. Draining rather than blocking is what keeps
    /// the interface responsive while a query is in flight.
    pub fn drain(&mut self) {
        while let Ok(update) = self.worker.updates.try_recv() {
            self.apply(update);
        }
    }

    fn apply(&mut self, update: Update) {
        match update {
            Update::Accounts { rows, append } => {
                self.observe(rows.iter().map(|a| a.ledger));
                self.rows = match (append, std::mem::take(&mut self.rows)) {
                    (true, Rows::Accounts(mut held)) => {
                        held.extend(rows);
                        Rows::Accounts(held)
                    }
                    _ => Rows::Accounts(rows),
                };
                self.loading = false;
            }
            Update::Transfers { rows, append } => {
                self.observe(rows.iter().map(|t| t.ledger));
                self.rows = match (append, std::mem::take(&mut self.rows)) {
                    (true, Rows::Transfers(mut held)) => {
                        held.extend(rows);
                        Rows::Transfers(held)
                    }
                    _ => Rows::Transfers(rows),
                };
                self.loading = false;
            }
            Update::Balances { rows } => {
                self.rows = Rows::Balances(rows);
                self.loading = false;
            }
            Update::Found(found) => {
                self.status = Some(match found {
                    tbclient::Found::Account(a) => format!("account {}", a.id),
                    tbclient::Found::Transfer(t) => format!("transfer {}", t.id),
                    tbclient::Found::Nothing => "no account or transfer with that id".to_string(),
                });
                self.loading = false;
            }
            Update::Latency(latency) => self.latency = Some(latency),
            Update::Failed(error) => self.fail(error),
        }
        self.clamp_selection();
    }

    fn fail(&mut self, error: TbError) {
        self.error = Some(error.to_string());
        self.loading = false;
    }

    fn observe(&mut self, ledgers: impl Iterator<Item = u32>) {
        for ledger in ledgers {
            if ledger != 0 && !self.ledgers.contains(&ledger) {
                self.ledgers.push(ledger);
            }
        }
        self.ledgers.sort_unstable();
    }

    fn clamp_selection(&mut self) {
        let len = self.rows.len();
        if len == 0 {
            self.selected = 0;
        } else if self.selected >= len {
            self.selected = len - 1;
        }
    }

    pub fn select_next(&mut self) {
        if !self.rows.is_empty() {
            self.selected = (self.selected + 1).min(self.rows.len() - 1);
        }
    }

    pub fn select_previous(&mut self) {
        self.selected = self.selected.saturating_sub(1);
    }

    pub fn select_first(&mut self) {
        self.selected = 0;
    }

    pub fn select_last(&mut self) {
        self.selected = self.rows.len().saturating_sub(1);
    }

    pub fn toggle_help(&mut self) {
        self.mode = match self.mode {
            Mode::Help => Mode::Normal,
            _ => Mode::Help,
        };
    }

    /// `esc`: out of help first, then back to the list. One rule, one key.
    pub fn back(&mut self) {
        match self.mode {
            Mode::Help => self.mode = Mode::Normal,
            Mode::Normal => {
                if self.status.is_some() || self.error.is_some() {
                    self.status = None;
                    self.error = None;
                } else if self.view != View::Accounts {
                    self.show(View::Accounts);
                }
            }
        }
    }

    pub fn toggle_order(&mut self) {
        self.newest_first = !self.newest_first;
        self.reload();
    }

    pub fn breadcrumbs(&self) -> String {
        let mut crumbs = vec![self.view.title().to_string()];
        if !self.rows.is_empty() {
            if let Rows::Accounts(rows) = &self.rows {
                if let Some(account) = rows.get(self.selected) {
                    crumbs.push(account.id.to_string());
                }
            }
        }
        crumbs.join(" › ")
    }
}
