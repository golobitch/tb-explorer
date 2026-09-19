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
    App::new(
        0,
        "127.0.0.1:3000".to_string(),
        Worker::detached(),
        crate::theme::Theme::detect(false),
    )
}

/// The same screen with colour off, for the tests that check the monochrome fallback.
fn plain_app() -> App {
    App::new(
        0,
        "127.0.0.1:3000".to_string(),
        Worker::detached(),
        crate::theme::Theme::detect(true),
    )
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
    assert!(
        screen.contains("1\u{202F}007\u{202F}430"),
        "exact, grouped, never rounded: {screen}"
    );
    assert!(
        screen.contains("855"),
        "net is credits minus debits: {screen}"
    );
    assert!(
        screen.contains("[1]"),
        "the title carries the count: {screen}"
    );
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
    assert!(render(&app, 120, 8).contains("-29\u{202F}885"));
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
    assert!(screen.contains("71\u{202F}001"), "{screen}");
    assert!(screen.contains("pending"), "{screen}");
    assert!(screen.contains("query_transfers"), "{screen}");
}

#[test]
fn help_lists_every_binding_and_covers_the_table() {
    let mut app = app();
    app.toggle_help();
    assert_eq!(app.mode, Mode::Help);
    let screen = render(&app, 100, 24);
    for (key, _) in crate::ui::overlay::KEYS {
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
    assert_eq!(app.crumbs(), ["accounts", "account 1015"]);

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
        app.crumbs(),
        ["accounts", "account 1015", "transfer 100539"]
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
    assert_eq!(app.crumbs(), ["transfers"]);
}

fn type_line(app: &mut App, text: &str) {
    for c in text.chars() {
        app.type_char(c);
    }
    app.submit_input();
}

#[test]
fn commands_open_views_by_name_and_by_alias() {
    let mut app = app();
    app.begin_command();
    type_line(&mut app, "transfers");
    assert_eq!(app.view, View::Transfers);

    app.begin_command();
    type_line(&mut app, "acc");
    assert_eq!(app.view, View::Accounts);

    app.begin_command();
    type_line(&mut app, "tx 100539");
    assert_eq!(app.view, View::Transfer { id: 100_539 });

    app.begin_command();
    type_line(&mut app, "bal 1017");
    assert_eq!(
        app.view,
        View::Account {
            id: 1017,
            balances: true
        }
    );
}

#[test]
fn an_unknown_command_says_so_rather_than_doing_nothing() {
    let mut app = app();
    app.begin_command();
    type_line(&mut app, "nonsense");
    let status = app.status.clone().expect("a message");
    assert!(status.contains("nonsense"), "{status}");
    assert!(status.contains("ctrl-a"), "it points at the list: {status}");
    assert_eq!(app.view, View::Accounts, "and it changes nothing");
}

#[test]
fn esc_cancels_a_half_typed_command() {
    let mut app = app();
    app.begin_command();
    app.type_char('t');
    app.back();
    assert_eq!(app.mode, Mode::Normal);
    assert!(app.input.is_empty());
    assert_eq!(app.view, View::Accounts);
}

#[test]
fn the_filter_narrows_the_rows_on_screen() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![
        Account {
            id: 1001,
            ledger: 700,
            ..Default::default()
        },
        Account {
            id: 1015,
            ledger: 840,
            ..Default::default()
        },
        Account {
            id: 1016,
            ledger: 840,
            ..Default::default()
        },
    ]);

    app.begin_filter();
    for c in "840".chars() {
        app.type_char(c);
    }
    assert_eq!(app.visible_len(), 2);

    let screen = render(&app, 120, 10);
    assert!(screen.contains("1015"), "{screen}");
    assert!(
        !screen.contains("1001"),
        "the filtered-out row is gone:\n{screen}"
    );

    app.backspace();
    app.backspace();
    app.backspace();
    assert_eq!(
        app.visible_len(),
        3,
        "an empty filter shows everything again"
    );
}

#[test]
fn a_filter_that_matches_nothing_says_which_kind_of_empty_it_is() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account {
        id: 1001,
        ..Default::default()
    }]);
    app.begin_filter();
    type_line(&mut app, "zzz");
    assert!(render(&app, 100, 8).contains("nothing matches this filter"));
}

#[test]
fn opening_a_filtered_row_opens_the_row_you_can_see() {
    let mut app = app();
    app.rows = Rows::Accounts(vec![
        Account {
            id: 1001,
            ledger: 700,
            ..Default::default()
        },
        Account {
            id: 1015,
            ledger: 840,
            ..Default::default()
        },
    ]);
    app.begin_filter();
    for c in "840".chars() {
        app.type_char(c);
    }
    app.mode = Mode::Normal;
    app.open_selection();
    assert_eq!(
        app.view,
        View::Account {
            id: 1015,
            balances: false
        },
        "the first visible row, not the first row"
    );
}

#[test]
fn ctrl_a_lists_every_command() {
    let mut app = app();
    app.show_commands();
    let screen = render(&app, 100, 24);
    for (command, _, _) in crate::app::COMMANDS {
        let head = command.split_whitespace().next().unwrap();
        assert!(screen.contains(head), "{command} missing:\n{screen}");
    }
}

#[test]
fn auto_refresh_holds_still_while_something_is_being_read() {
    use std::time::Duration;
    let mut app = app();
    app.toggle_auto_refresh();
    assert!(app.auto_refresh);

    // Zero interval, so only the guards decide.
    let due = Duration::from_millis(0);
    assert!(
        app.should_auto_refresh(due),
        "at the top of a list it may refresh"
    );

    app.rows = Rows::Accounts(vec![Account::default(), Account::default()]);
    app.select_next();
    assert!(!app.should_auto_refresh(due), "not while a row is selected");

    app.select_first();
    app.stack.push(View::Accounts);
    assert!(
        !app.should_auto_refresh(due),
        "not while a detail view is open"
    );

    app.stack.clear();
    app.begin_filter();
    assert!(!app.should_auto_refresh(due), "not while typing");
}

// Styles, not just text: TestBackend's buffer carries them, so the colours are testable.

fn style_of(app: &App, width: u16, height: u16, needle: &str) -> ratatui::style::Style {
    let mut terminal = Terminal::new(TestBackend::new(width, height)).unwrap();
    terminal.draw(|frame| crate::ui::draw(frame, app)).unwrap();
    let buffer = terminal.backend().buffer().clone();
    let first = needle.chars().next().unwrap();
    for y in 0..buffer.area.height {
        for x in 0..buffer.area.width {
            if buffer[(x, y)].symbol().starts_with(first) {
                let run: String = (x..buffer.area.width)
                    .map(|i| buffer[(i, y)].symbol().to_string())
                    .collect();
                if run.starts_with(needle) {
                    return buffer[(x, y)].style();
                }
            }
        }
    }
    panic!("{needle:?} is not on screen");
}

#[test]
fn a_flag_wears_the_colour_the_macos_app_gives_it() {
    use ratatui::style::Color;
    let mut app = app();
    app.loading = false;
    app.view = View::Transfers;
    app.rows = Rows::Transfers(vec![Transfer {
        id: 100_539,
        flags: tbclient::models::transfer_flags::PENDING,
        ..Default::default()
    }]);
    assert_eq!(style_of(&app, 130, 12, "pending").fg, Some(Color::Yellow));
}

#[test]
fn a_negative_net_is_red_and_a_positive_one_is_not() {
    use ratatui::style::Color;
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account {
        id: 1017,
        debits_posted: 968_201,
        credits_posted: 938_316,
        ledger: 840,
        ..Default::default()
    }]);
    assert_eq!(style_of(&app, 130, 12, "-29").fg, Some(Color::Red));

    app.rows = Rows::Accounts(vec![Account {
        id: 1015,
        debits_posted: 1,
        credits_posted: 856,
        ledger: 840,
        ..Default::default()
    }]);
    // Unstyled cells report Reset rather than None; either way, not red.
    assert_ne!(style_of(&app, 130, 12, "855").fg, Some(Color::Red));
}

#[test]
fn the_wordmark_turns_red_when_a_query_fails() {
    use ratatui::style::Color;
    let mut app = app();
    app.loading = false;
    assert_eq!(style_of(&app, 130, 24, "####").fg, Some(Color::Cyan));

    app.error = Some("no answer within 10.0s".to_string());
    assert_eq!(style_of(&app, 130, 24, "####").fg, Some(Color::Red));
}

#[test]
fn no_color_leaves_no_colour_anywhere() {
    let mut app = plain_app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account {
        id: 1017,
        debits_posted: 968_201,
        credits_posted: 938_316,
        ledger: 840,
        flags: tbclient::models::account_flags::HISTORY,
        ..Default::default()
    }]);

    let mut terminal = Terminal::new(TestBackend::new(130, 24)).unwrap();
    terminal.draw(|frame| crate::ui::draw(frame, &app)).unwrap();
    let buffer = terminal.backend().buffer().clone();
    for y in 0..buffer.area.height {
        for x in 0..buffer.area.width {
            let style = buffer[(x, y)].style();
            // Reset is the absence of a colour; anything else would be one.
            let plain = |colour: Option<ratatui::style::Color>| {
                matches!(colour, None | Some(ratatui::style::Color::Reset))
            };
            assert!(plain(style.fg), "colour {:?} at {x},{y}", style.fg);
            assert!(plain(style.bg), "background {:?} at {x},{y}", style.bg);
        }
    }
}

#[test]
fn f_switches_amounts_into_the_ledgers_currency() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account {
        id: 1015,
        debits_posted: 1_063_827,
        ledger: 840,
        ..Default::default()
    }]);
    assert!(render(&app, 130, 12).contains("1\u{202F}063\u{202F}827"));

    app.toggle_currency();
    let screen = render(&app, 130, 12);
    assert!(screen.contains("10\u{202F}638.27 $"), "{screen}");
    assert!(screen.contains("840 · USD"), "{screen}");

    app.toggle_currency();
    assert!(
        render(&app, 130, 12).contains("1\u{202F}063\u{202F}827"),
        "and back again"
    );
}

#[test]
fn a_ledger_that_is_not_a_currency_is_left_alone_even_in_currency_mode() {
    let mut app = app();
    app.loading = false;
    app.toggle_currency();
    app.rows = Rows::Accounts(vec![Account {
        id: 1001,
        debits_posted: 1_063_827,
        ledger: 700,
        ..Default::default()
    }]);
    let screen = render(&app, 130, 12);
    assert!(screen.contains("1\u{202F}063\u{202F}827"), "{screen}");
    assert!(!screen.contains("$"), "{screen}");
}

#[test]
fn the_title_names_the_view_its_operation_and_its_count() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Accounts(vec![Account::default(), Account::default()]);
    let screen = render(&app, 130, 12);
    assert!(screen.contains("accounts(query_accounts)[2]"), "{screen}");
    assert!(
        screen.contains("1/2"),
        "the cursor's place in the list: {screen}"
    );
}

#[test]
fn a_detail_view_shows_the_fields_above_the_table() {
    let mut app = app();
    app.view = View::Account {
        id: 1017,
        balances: false,
    };
    app.account = Some(Account {
        id: 1017,
        debits_posted: 968_201,
        credits_posted: 938_316,
        credits_pending: 71_001,
        ledger: 840,
        code: 2,
        ..Default::default()
    });
    app.loading = false;
    app.rows = Rows::Transfers(vec![Transfer {
        id: 100_004,
        ledger: 840,
        ..Default::default()
    }]);

    let screen = render(&app, 130, 24);
    assert!(screen.contains("account 1017"), "{screen}");
    assert!(
        screen.contains("968\u{202F}201"),
        "its own figures: {screen}"
    );
    assert!(screen.contains("-29\u{202F}885"), "its net: {screen}");
    assert!(
        screen.contains("transfers(get_account_transfers)"),
        "and the table beneath: {screen}"
    );
}

#[test]
fn the_header_collapses_on_a_small_terminal() {
    let app = app();
    let wide = render(&app, 130, 24);
    assert!(wide.contains("context"), "the framed header at full size");

    let short = render(&app, 130, 18);
    assert!(
        !short.contains("╭ context"),
        "too few rows for a frame:\n{short}"
    );
    assert!(short.contains("READ-ONLY"), "but never without the badge");

    let narrow = render(&app, 80, 24);
    assert!(!narrow.contains("╭ context"), "too few columns:\n{narrow}");
}

#[test]
fn reaching_the_end_of_a_page_asks_for_the_next_one() {
    let mut app = app();
    app.loading = false;
    app.rows = Rows::Transfers(vec![
        Transfer {
            id: 1,
            timestamp: 10,
            ..Default::default()
        },
        Transfer {
            id: 2,
            timestamp: 11,
            ..Default::default()
        },
    ]);
    app.view = View::Transfers;

    app.select_next();
    assert!(app.loading, "the last row asks for more");

    app.loading = false;
    app.select_previous();
    app.select_next();
    assert!(app.loading, "and asks again when it returns to the end");
}

#[test]
fn a_filtered_list_does_not_page_behind_the_filter() {
    let mut app = app();
    app.loading = false;
    app.view = View::Transfers;
    app.rows = Rows::Transfers(vec![
        Transfer {
            id: 1,
            ledger: 700,
            timestamp: 10,
            ..Default::default()
        },
        Transfer {
            id: 2,
            ledger: 840,
            timestamp: 11,
            ..Default::default()
        },
    ]);
    app.begin_filter();
    for c in "840".chars() {
        app.type_char(c);
    }
    app.mode = crate::app::Mode::Normal;

    app.select_next();
    assert!(
        !app.loading,
        "the end of a filtered view is not the end of the query"
    );
}
