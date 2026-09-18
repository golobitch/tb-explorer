//! Headless rendering checks.
//!
//! `TestBackend` draws into a buffer, so layout, the header and the help overlay can be asserted
//! without a terminal — the closest the TUI gets to the macOS app's snapshot runs.

use ratatui::Terminal;
use ratatui::backend::TestBackend;
use tbclient::{Account, Transfer};

use crate::app::{App, Mode, Rows, View};
use crate::worker::Worker;

/// An app with no cluster behind it: queries go nowhere and no answer ever arrives.
fn app() -> App {
    App::new(0, "127.0.0.1:3000".to_string(), Worker::detached())
}

fn render(app: &App, width: u16, height: u16) -> String {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
    terminal.draw(|frame| crate::ui::draw(frame, app)).unwrap();
    let buffer = terminal.backend().buffer().clone();
    (0..buffer.area.height)
        .map(|y| {
            (0..buffer.area.width)
                .map(|x| buffer[(x, y)].symbol().to_string())
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[test]
fn the_header_says_what_it_is_connected_to_and_that_it_cannot_write() {
    let app = app();
    let screen = render(&app, 120, 10);
    assert!(screen.contains("tb-tui"), "{screen}");
    assert!(screen.contains("cluster 0"), "{screen}");
    assert!(screen.contains("127.0.0.1:3000"), "{screen}");
    assert!(screen.contains("READ-ONLY"), "{screen}");
    assert!(screen.contains("query_accounts"), "{screen}");
}

#[test]
fn an_empty_view_says_so_rather_than_drawing_an_empty_table() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(Vec::new());
    assert!(render(&app, 80, 8).contains("nothing here"));
}

#[test]
fn accounts_render_with_their_exact_amounts() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account {
        id: 1015,
        debits_posted: 1_007_430,
        credits_posted: 1_008_285,
        ledger: 840,
        code: 1,
        ..Default::default()
    }]);
    let screen = render(&app, 120, 8);
    assert!(screen.contains("1015"), "{screen}");
    assert!(screen.contains("1007430"), "exact, never rounded: {screen}");
    assert!(
        screen.contains("855"),
        "net is credits minus debits: {screen}"
    );
    assert!(screen.contains("1 accounts"), "{screen}");
}

#[test]
fn a_negative_net_keeps_its_sign() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account {
        id: 1017,
        debits_posted: 968_201,
        credits_posted: 938_316,
        ledger: 840,
        ..Default::default()
    }]);
    assert!(render(&app, 120, 8).contains("-29885"));
}

#[test]
fn transfers_render_both_sides() {
    let mut app = app();
    app.loading = false;
    app.view = View::Transfers;
    app.rows = Rows::Transfers(vec![Transfer {
        id: 100_539,
        debit_account_id: 1016,
        credit_account_id: 1017,
        amount: 71_001,
        ledger: 840,
        code: 20,
        flags: tbclient::models::transfer_flags::PENDING,
        ..Default::default()
    }]);
    let screen = render(&app, 130, 8);
    assert!(screen.contains("100539"), "{screen}");
    assert!(screen.contains("1016"), "{screen}");
    assert!(screen.contains("71001"), "{screen}");
    assert!(screen.contains("pending"), "{screen}");
    assert!(screen.contains("query_transfers"), "{screen}");
}

#[test]
fn help_lists_every_binding_and_covers_the_table() {
    let mut app = app();
    app.toggle_help();
    assert_eq!(app.mode, Mode::Help);
    let screen = render(&app, 100, 24);
    for (key, _) in crate::ui::KEYS {
        assert!(screen.contains(key), "{key} missing from help:\n{screen}");
    }
    assert!(screen.contains("read-only"), "{screen}");
}

#[test]
fn a_failed_query_is_shown_with_a_way_out() {
    let mut app = app();
    app.error = Some("no answer within 10.0s".to_string());
    let screen = render(&app, 80, 10);
    assert!(screen.contains("Query failed"), "{screen}");
    assert!(screen.contains("ctrl-r retries"), "{screen}");
}

#[test]
fn esc_leaves_help_before_it_leaves_the_view() {
    let mut app = app();
    app.show(View::Transfers);
    app.toggle_help();

    app.back();
    assert_eq!(app.mode, Mode::Normal, "esc leaves help first");
    assert_eq!(app.view, View::Transfers);

    app.back();
    assert_eq!(
        app.view,
        View::Transfers,
        "a top-level view has nothing behind it, so esc stays put"
    );
}

#[test]
fn selection_stays_inside_the_rows() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![Account::default(), Account::default()]);
    app.select_last();
    assert_eq!(app.selected, 1);
    app.select_next();
    assert_eq!(app.selected, 1, "the last row is the last row");
    app.select_previous();
    app.select_previous();
    assert_eq!(app.selected, 0);

    app.rows = Rows::Accounts(vec![Account::default()]);
    app.select_last();
    app.rows = Rows::Accounts(Vec::new());
    app.select_next();
    assert_eq!(app.selected, 0, "an empty view has nothing to select");
}

#[test]
fn enter_opens_the_selected_row_and_esc_comes_back() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![
        Account {
            id: 1001,
            ..Default::default()
        },
        Account {
            id: 1015,
            ..Default::default()
        },
    ]);
    app.select_next();
    app.open_selection();

    assert_eq!(
        app.view,
        View::Account {
            id: 1015,
            balances: false
        }
    );
    assert_eq!(app.breadcrumbs(), "accounts › account 1015");

    app.back();
    assert_eq!(
        app.view,
        View::Accounts,
        "esc returns to where it came from"
    );
    assert!(app.stack.is_empty());
}

#[test]
fn the_stack_goes_deeper_than_one_step() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![Account {
        id: 1015,
        ..Default::default()
    }]);
    app.open_selection();
    app.rows = Rows::Transfers(vec![Transfer {
        id: 100_539,
        ..Default::default()
    }]);
    app.open_selection();

    assert_eq!(app.view, View::Transfer { id: 100_539 });
    assert_eq!(
        app.breadcrumbs(),
        "accounts › account 1015 › transfer 100539"
    );

    app.back();
    assert_eq!(
        app.view,
        View::Account {
            id: 1015,
            balances: false
        }
    );
    app.back();
    assert_eq!(app.view, View::Accounts);
}

#[test]
fn b_swaps_an_accounts_transfers_for_its_balances_without_going_deeper() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![Account {
        id: 1017,
        ..Default::default()
    }]);
    app.open_selection();
    let depth = app.stack.len();

    app.toggle_balances();
    assert_eq!(
        app.view,
        View::Account {
            id: 1017,
            balances: true
        }
    );
    assert_eq!(
        app.stack.len(),
        depth,
        "balances are the same place, seen differently"
    );
    assert!(render(&app, 120, 8).contains("get_account_balances"));
}

#[test]
fn a_top_level_view_clears_the_trail() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![Account {
        id: 1015,
        ..Default::default()
    }]);
    app.open_selection();
    app.show(View::Transfers);

    assert!(
        app.stack.is_empty(),
        "`2` is a fresh start, not a step deeper"
    );
    assert_eq!(app.breadcrumbs(), "transfers");
}
