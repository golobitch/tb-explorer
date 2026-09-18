//! What is on screen, and what the keys do to it.

use std::time::{Duration, Instant};

use tbclient::{
    Account, AccountFilter, Balance, Chain, DEFAULT_LOOKBACK, QueryFilter, TbError, Transfer,
};

use crate::worker::{Query, Update, Worker};

/// One screen. The stack of these is what `esc` walks back up.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum View {
    Accounts,
    Transfers,
    Ledgers,
    /// One account: its transfers, or its balance history.
    Account {
        id: u128,
        balances: bool,
    },
    /// One transfer, with whatever chain it belongs to.
    Transfer {
        id: u128,
    },
}

impl View {
    pub fn title(&self) -> String {
        match self {
            Self::Accounts => "accounts".to_string(),
            Self::Transfers => "transfers".to_string(),
            Self::Ledgers => "ledgers".to_string(),
            Self::Account { id, balances } => {
                format!("account {id}{}", if *balances { " › balances" } else { "" })
            }
            Self::Transfer { id } => format!("transfer {id}"),
        }
    }

    /// The operation behind the view, shown in the header the way the macOS app shows it.
    pub fn operation(&self) -> &'static str {
        match self {
            Self::Accounts => "query_accounts",
            Self::Transfers => "query_transfers",
            Self::Ledgers => "collected while browsing",
            Self::Account {
                balances: false, ..
            } => "get_account_transfers",
            Self::Account { balances: true, .. } => "get_account_balances",
            Self::Transfer { .. } => "lookup_transfers",
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub enum Mode {
    #[default]
    Normal,
    Help,
    /// `:` — ask the cluster something new.
    Command,
    /// `/` — narrow what is already on screen.
    Filter,
    /// `ctrl-a` — every command, for when you cannot remember one.
    Commands,
}

/// What `:` understands. Aliases are listed because a command you cannot remember is a command you
/// do not have; `ctrl-a` shows this table.
pub const COMMANDS: &[(&str, &str, &str)] = &[
    ("accounts", "acc, a", "every account"),
    ("transfers", "tx, t", "every transfer"),
    ("ledgers", "l", "ledgers seen so far"),
    ("account <id>", "acc <id>", "one account's transfers"),
    ("balances <id>", "bal <id>", "one account's balance history"),
    ("transfer <id>", "tx <id>", "one transfer and its chain"),
    ("<id>", "", "whichever of the two that id names"),
];

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

pub struct App {
    pub cluster_id: u128,
    pub addresses: String,
    pub latency: Option<Duration>,
    pub view: View,
    /// Where `esc` goes back to. A k9s habit: one key, one step.
    pub stack: Vec<View>,
    pub rows: Rows,
    pub chain: Option<Box<Chain>>,
    pub selected: usize,
    pub mode: Mode,
    pub status: Option<String>,
    pub error: Option<String>,
    pub loading: bool,
    /// Ledgers are not enumerable in TigerBeetle, so they are collected from what has been seen —
    /// the same approach the macOS app takes.
    pub ledgers: Vec<u32>,
    pub newest_first: bool,
    /// Re-runs the current query on a timer. Paused while a row is selected or a detail view is
    /// open: a list that moves under the cursor is the one thing that makes k9s unpleasant, and
    /// this is a tool for reading carefully.
    pub auto_refresh: bool,
    pub input: String,
    pub filter: String,
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
            stack: Vec::new(),
            rows: Rows::None,
            chain: None,
            selected: 0,
            mode: Mode::Normal,
            status: None,
            error: None,
            loading: false,
            ledgers: Vec::new(),
            newest_first: false,
            auto_refresh: false,
            input: String::new(),
            filter: String::new(),
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
            View::Account { id, balances } => {
                let filter = AccountFilter {
                    account_id: id,
                    limit: 200,
                    reversed: self.newest_first,
                    ..Default::default()
                };
                if balances {
                    self.worker.send(Query::AccountBalances { filter });
                } else {
                    self.worker.send(Query::AccountTransfers {
                        filter,
                        append: false,
                    });
                }
            }
            View::Transfer { id } => {
                self.chain = None;
                self.worker.send(Query::Chain {
                    id,
                    lookback: DEFAULT_LOOKBACK,
                });
            }
        }
    }

    /// Opens a view and remembers where it came from.
    pub fn push(&mut self, view: View) {
        if self.view == view {
            return;
        }
        self.stack.push(self.view.clone());
        self.view = view;
        self.selected = 0;
        self.rows = Rows::None;
        self.reload();
    }

    /// Opens whatever the selected row points at: an account from a list of accounts, a transfer
    /// from a list of transfers, a ledger's accounts from the ledger list.
    pub fn open_selection(&mut self) {
        let Some(row) = self.selected_row() else {
            return;
        };
        let next = match &self.rows {
            Rows::Accounts(rows) => rows.get(row).map(|a| View::Account {
                id: a.id,
                balances: false,
            }),
            Rows::Transfers(rows) => rows.get(row).map(|t| View::Transfer { id: t.id }),
            Rows::Ledgers(rows) => rows.get(row).map(|_| View::Accounts),
            _ => None,
        };
        if let Some(next) = next {
            self.push(next);
        }
    }

    /// `b` on an account swaps its transfers for its balance history, in place.
    pub fn toggle_balances(&mut self) {
        if let View::Account { id, balances } = self.view {
            self.view = View::Account {
                id,
                balances: !balances,
            };
            self.selected = 0;
            self.rows = Rows::None;
            self.reload();
        }
    }

    /// A top-level view: the stack starts over, the way k9s's `:` command does.
    pub fn show(&mut self, view: View) {
        if self.view != view {
            self.stack.clear();
            self.chain = None;
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
            Update::Chain(chain) => {
                self.rows = Rows::Transfers(chain_rows(&chain));
                self.chain = Some(chain);
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

    pub fn visible_len(&self) -> usize {
        self.visible_rows().len()
    }

    /// The index into `rows` behind the current selection, once the filter has had its say.
    pub fn selected_row(&self) -> Option<usize> {
        self.visible_rows().get(self.selected).copied()
    }

    fn clamp_selection(&mut self) {
        let len = self.visible_len();
        if len == 0 {
            self.selected = 0;
        } else if self.selected >= len {
            self.selected = len - 1;
        }
    }

    pub fn select_next(&mut self) {
        let len = self.visible_len();
        if len > 0 {
            self.selected = (self.selected + 1).min(len - 1);
        }
    }

    pub fn select_previous(&mut self) {
        self.selected = self.selected.saturating_sub(1);
    }

    pub fn select_first(&mut self) {
        self.selected = 0;
    }

    pub fn select_last(&mut self) {
        self.selected = self.visible_len().saturating_sub(1);
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
            Mode::Help | Mode::Commands => self.mode = Mode::Normal,
            Mode::Command | Mode::Filter => self.cancel_input(),
            Mode::Normal => {
                if self.status.is_some() || self.error.is_some() {
                    self.status = None;
                    self.error = None;
                } else if let Some(previous) = self.stack.pop() {
                    self.view = previous;
                    self.selected = 0;
                    self.rows = Rows::None;
                    self.chain = None;
                    self.reload();
                }
            }
        }
    }

    pub fn toggle_order(&mut self) {
        self.newest_first = !self.newest_first;
        self.reload();
    }

    pub fn begin_command(&mut self) {
        self.mode = Mode::Command;
        self.input.clear();
    }

    pub fn begin_filter(&mut self) {
        self.mode = Mode::Filter;
        self.input = self.filter.clone();
    }

    pub fn show_commands(&mut self) {
        self.mode = Mode::Commands;
    }

    pub fn type_char(&mut self, c: char) {
        self.input.push(c);
        if self.mode == Mode::Filter {
            self.filter = self.input.clone();
            self.selected = 0;
        }
    }

    pub fn backspace(&mut self) {
        self.input.pop();
        if self.mode == Mode::Filter {
            self.filter = self.input.clone();
            self.selected = 0;
        }
    }

    pub fn cancel_input(&mut self) {
        if self.mode == Mode::Filter {
            self.filter.clear();
        }
        self.input.clear();
        self.mode = Mode::Normal;
    }

    /// Runs what was typed after `:`. An unknown command says so rather than doing nothing.
    pub fn submit_input(&mut self) {
        let typed = self.input.trim().to_string();
        self.input.clear();
        let mode = std::mem::take(&mut self.mode);
        if mode == Mode::Filter || typed.is_empty() {
            return;
        }

        let mut words = typed.split_whitespace();
        let command = words.next().unwrap_or_default();
        let argument = words.next().and_then(|a| a.parse::<u128>().ok());

        match (command, argument) {
            ("accounts" | "acc" | "a", None) => self.show(View::Accounts),
            ("transfers" | "tx" | "t", None) => self.show(View::Transfers),
            ("ledgers" | "l", None) => self.show(View::Ledgers),
            ("account" | "acc" | "a", Some(id)) => self.push(View::Account {
                id,
                balances: false,
            }),
            ("balances" | "bal", Some(id)) => self.push(View::Account { id, balances: true }),
            ("transfer" | "tx" | "t", Some(id)) => self.push(View::Transfer { id }),
            ("help" | "h" | "?", _) => self.mode = Mode::Help,
            ("q" | "quit", _) => self.quit = true,
            _ => match command.parse::<u128>() {
                // A bare id is the commonest thing to paste, so it needs no command at all.
                Ok(id) => {
                    self.loading = true;
                    self.worker.send(Query::Lookup { id });
                }
                Err(_) => self.status = Some(format!("no command “{typed}” — ctrl-a lists them")),
            },
        }
    }

    /// The rows left after `/`. Filtering happens here rather than at the cluster because
    /// TigerBeetle only filters on the fields its query filters carry.
    pub fn visible_rows(&self) -> Vec<usize> {
        let needle = self.filter.trim().to_lowercase();
        let matches =
            |haystack: String| needle.is_empty() || haystack.to_lowercase().contains(&needle);
        match &self.rows {
            Rows::Accounts(rows) => rows
                .iter()
                .enumerate()
                .filter(|(_, a)| {
                    matches(format!(
                        "{} {} {} {}",
                        a.id,
                        a.ledger,
                        a.code,
                        a.flag_names().join(" ")
                    ))
                })
                .map(|(i, _)| i)
                .collect(),
            Rows::Transfers(rows) => rows
                .iter()
                .enumerate()
                .filter(|(_, t)| {
                    matches(format!(
                        "{} {} {} {} {} {} {}",
                        t.id,
                        t.debit_account_id,
                        t.credit_account_id,
                        t.amount,
                        t.ledger,
                        t.code,
                        t.flag_names().join(" ")
                    ))
                })
                .map(|(i, _)| i)
                .collect(),
            Rows::Balances(rows) => (0..rows.len()).collect(),
            Rows::Ledgers(rows) => rows
                .iter()
                .enumerate()
                .filter(|(_, l)| matches(l.to_string()))
                .map(|(i, _)| i)
                .collect(),
            Rows::None => Vec::new(),
        }
    }

    pub fn toggle_auto_refresh(&mut self) {
        self.auto_refresh = !self.auto_refresh;
        self.last_refresh = Instant::now();
    }

    /// True when the timer is due and nothing is being read closely.
    pub fn should_auto_refresh(&self, every: Duration) -> bool {
        self.auto_refresh
            && self.mode == Mode::Normal
            && self.selected == 0
            && self.stack.is_empty()
            && self.last_refresh.elapsed() >= every
    }

    /// Where you are, and how you got here.
    pub fn breadcrumbs(&self) -> String {
        let mut crumbs: Vec<String> = self.stack.iter().map(|view| view.title()).collect();
        crumbs.push(self.view.title());
        crumbs.join(" › ")
    }
}

/// A chain reads as one list: the pending transfer, the transfer itself, whatever resolved it and
/// the rest of its linked group, in the order they happened.
fn chain_rows(chain: &Chain) -> Vec<Transfer> {
    let mut rows = vec![chain.transfer];
    if let Some(pending) = chain.pending {
        rows.push(pending);
    }
    if let Some(resolution) = &chain.resolution {
        rows.extend(resolution.resolutions.iter().copied());
    }
    rows.extend(chain.linked.iter().copied());
    rows.sort_by_key(|t| t.timestamp);
    rows.dedup_by_key(|t| t.id);
    rows
}
