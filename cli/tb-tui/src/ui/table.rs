//! The tables: framed, titled with a count, with a cursor bar and a scrollbar.

use ratatui::Frame;
use ratatui::layout::{Constraint, Margin, Rect};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{
    Block, BorderType, Cell, HighlightSpacing, Paragraph, Row, Scrollbar, ScrollbarOrientation,
    ScrollbarState, Table, TableState,
};

use crate::app::{App, Rows};
use crate::theme::Theme;

/// ` accounts(ledger 840)[20] ` — name, scope, count, each in its own colour, as k9s titles tables.
pub struct Title {
    pub name: String,
    pub scope: Option<String>,
}

pub fn title(app: &App) -> Title {
    Title {
        name: app.view.title(),
        scope: Some(app.view.operation().to_string()),
    }
}

pub fn draw(frame: &mut Frame, area: Rect, app: &App, title: Title) {
    let theme = &app.theme;
    let visible = app.visible_rows();

    let block = framed(app, &title, visible.len());
    if visible.is_empty() {
        let lines = if let Some(error) = &app.error {
            vec![
                Line::from(Span::styled("Query failed", theme.bad)),
                Line::raw(""),
                Line::from(Span::raw(error.clone())),
                Line::raw(""),
                Line::from(Span::styled("ctrl-r retries · esc dismisses", theme.hint)),
            ]
        } else {
            let text = if app.loading {
                "loading…"
            } else if !app.filter.is_empty() {
                "nothing matches this filter"
            } else {
                "nothing here"
            };
            vec![Line::from(Span::styled(text, theme.hint))]
        };
        frame.render_widget(Paragraph::new(lines).block(block), area);
        return;
    }

    let inner_height = area.height.saturating_sub(3) as usize; // borders and header row
    let mut state = TableState::default()
        .with_selected(Some(app.selected))
        .with_offset(app.scroll_offset(inner_height));

    // A squeezed id column is worse than no code column: ids are what a reader carries away.
    let narrow = area.width < 110;
    let (header, widths, rows) = match &app.rows {
        Rows::Accounts(all) => accounts(app, &visible, all, narrow),
        Rows::Transfers(all) => transfers(app, &visible, all, narrow),
        Rows::Balances(all) => balances(app, &visible, all, narrow),
        Rows::Ledgers(all) => ledgers(app, &visible, all),
        Rows::None => return,
    };

    let table = Table::new(rows, widths)
        .header(header.style(theme.header))
        .row_highlight_style(theme.cursor)
        .highlight_symbol(Text::from("\u{258C}"))
        // Without this the table jumps sideways the first time a row is selected.
        .highlight_spacing(HighlightSpacing::Always)
        .column_spacing(2)
        .block(block);
    frame.render_stateful_widget(table, area, &mut state);

    if visible.len() > inner_height {
        let mut scroll = ScrollbarState::new(visible.len())
            .position(app.selected)
            .viewport_content_length(inner_height);
        frame.render_stateful_widget(
            Scrollbar::new(ScrollbarOrientation::VerticalRight)
                // No arrows: ↑ and ↓ are ambiguous width and shift the frame in some terminals.
                .begin_symbol(None)
                .end_symbol(None)
                .thumb_symbol("\u{2588}")
                .track_symbol(Some("\u{2502}"))
                .thumb_style(theme.border_focus)
                .track_style(theme.border),
            area.inner(Margin {
                vertical: 1,
                horizontal: 0,
            }),
            &mut scroll,
        );
    }
}

fn framed<'a>(app: &App, title: &Title, count: usize) -> Block<'a> {
    let theme = &app.theme;
    let mut spans = vec![
        Span::raw(" "),
        Span::styled(title.name.clone(), theme.title),
    ];
    if let Some(scope) = &title.scope {
        spans.push(Span::styled(format!("({scope})"), theme.title_scope));
    }
    spans.push(Span::styled(format!("[{count}] "), theme.title_count));

    let mut block = Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(theme.border_focus)
        .title(Line::from(spans));

    if count > 0 {
        block = block.title_bottom(
            Line::from(Span::styled(
                format!(" {}/{count} ", app.selected + 1),
                theme.title_count,
            ))
            .right_aligned(),
        );
    }
    block
}

/// Numbers line up on the right, where the eye compares them.
fn number<'a>(text: String, style: ratatui::style::Style) -> Cell<'a> {
    Cell::from(Text::from(text).right_aligned()).style(style)
}

fn flags_cell<'a>(theme: &Theme, names: &[String]) -> Cell<'a> {
    let mut spans = Vec::new();
    for (i, name) in names.iter().enumerate() {
        if i > 0 {
            spans.push(Span::raw(" "));
        }
        spans.push(Span::styled(name.clone(), theme.flag(name)));
    }
    Cell::from(Line::from(spans))
}

/// One step of shading per row, so a wide row stays readable across the screen.
fn stripe(theme: &Theme, index: usize) -> ratatui::style::Style {
    if index % 2 == 1 {
        theme.stripe
    } else {
        ratatui::style::Style::new()
    }
}

type Built<'a> = (Row<'a>, Vec<Constraint>, Vec<Row<'a>>);

fn accounts<'a>(
    app: &App,
    visible: &[usize],
    all: &[tbclient::Account],
    narrow: bool,
) -> Built<'a> {
    let theme = &app.theme;
    let mut header = vec![Cell::from("id"), Cell::from("ledger")];
    let mut widths = vec![Constraint::Length(20), Constraint::Length(10)];
    if !narrow {
        header.extend([
            Cell::from("code"),
            Cell::from(Text::from("debits posted").right_aligned()),
            Cell::from(Text::from("credits posted").right_aligned()),
        ]);
        widths.extend([
            Constraint::Length(5),
            Constraint::Length(16),
            Constraint::Length(16),
        ]);
    }
    header.push(Cell::from(Text::from("net").right_aligned()));
    widths.push(Constraint::Length(16));
    header.push(Cell::from("flags"));
    widths.push(Constraint::Min(if narrow { 10 } else { 22 }));
    let header = Row::new(header);
    let rows = visible
        .iter()
        .filter_map(|&i| all.get(i))
        .enumerate()
        .map(|(position, account)| {
            let (net, negative) = account.net_posted();
            let mut cells = vec![
                Cell::from(account.id.to_string()).style(theme.id),
                Cell::from(app.amounts.ledger(account.ledger)),
            ];
            if !narrow {
                cells.push(Cell::from(account.code.to_string()));
                cells.push(number(
                    app.amounts.amount(account.debits_posted, account.ledger),
                    theme.number,
                ));
                cells.push(number(
                    app.amounts.amount(account.credits_posted, account.ledger),
                    theme.number,
                ));
            }
            cells.push(number(
                app.amounts.signed(net, negative, account.ledger),
                theme.net(negative),
            ));
            cells.push(flags_cell(theme, &account.flag_names()));
            Row::new(cells).style(stripe(theme, position))
        })
        .collect();
    (header, widths, rows)
}

fn transfers<'a>(
    app: &App,
    visible: &[usize],
    all: &[tbclient::Transfer],
    narrow: bool,
) -> Built<'a> {
    let theme = &app.theme;
    let mut header = vec![
        Cell::from("id"),
        Cell::from("debit"),
        Cell::from("credit"),
        Cell::from(Text::from("amount").right_aligned()),
    ];
    let mut widths = vec![
        Constraint::Length(20),
        Constraint::Length(12),
        Constraint::Length(12),
        Constraint::Length(16),
    ];
    if !narrow {
        header.extend([Cell::from("ledger"), Cell::from("code")]);
        widths.extend([Constraint::Length(10), Constraint::Length(5)]);
    }
    header.push(Cell::from("flags"));
    widths.push(Constraint::Min(if narrow { 10 } else { 24 }));
    let header = Row::new(header);
    let rows = visible
        .iter()
        .filter_map(|&i| all.get(i))
        .enumerate()
        .map(|(position, transfer)| {
            let mut cells = vec![
                Cell::from(transfer.id.to_string()).style(theme.id),
                Cell::from(transfer.debit_account_id.to_string()).style(theme.id),
                Cell::from(transfer.credit_account_id.to_string()).style(theme.id),
                number(
                    app.amounts.amount(transfer.amount, transfer.ledger),
                    theme.number,
                ),
            ];
            if !narrow {
                cells.push(Cell::from(app.amounts.ledger(transfer.ledger)));
                cells.push(Cell::from(transfer.code.to_string()));
            }
            cells.push(flags_cell(theme, &transfer.flag_names()));
            Row::new(cells).style(stripe(theme, position))
        })
        .collect();
    (header, widths, rows)
}

fn balances<'a>(
    app: &App,
    visible: &[usize],
    all: &[tbclient::Balance],
    _narrow: bool,
) -> Built<'a> {
    let theme = &app.theme;
    let ledger = app.view_ledger();
    let header = Row::new(vec![
        Cell::from("timestamp"),
        Cell::from(Text::from("debits pending").right_aligned()),
        Cell::from(Text::from("debits posted").right_aligned()),
        Cell::from(Text::from("credits pending").right_aligned()),
        Cell::from(Text::from("credits posted").right_aligned()),
        Cell::from(Text::from("net").right_aligned()),
    ]);
    let widths = vec![
        Constraint::Length(21),
        Constraint::Min(12),
        Constraint::Min(12),
        Constraint::Min(12),
        Constraint::Min(12),
        Constraint::Min(12),
    ];
    let rows = visible
        .iter()
        .filter_map(|&i| all.get(i))
        .enumerate()
        .map(|(position, balance)| {
            let (net, negative) = balance.net_posted();
            Row::new(vec![
                Cell::from(balance.timestamp.to_string()).style(theme.id),
                number(
                    app.amounts.amount(balance.debits_pending, ledger),
                    theme.number,
                ),
                number(
                    app.amounts.amount(balance.debits_posted, ledger),
                    theme.number,
                ),
                number(
                    app.amounts.amount(balance.credits_pending, ledger),
                    theme.number,
                ),
                number(
                    app.amounts.amount(balance.credits_posted, ledger),
                    theme.number,
                ),
                number(
                    app.amounts.signed(net, negative, ledger),
                    theme.net(negative),
                ),
            ])
            .style(stripe(theme, position))
        })
        .collect();
    (header, widths, rows)
}

fn ledgers<'a>(app: &App, visible: &[usize], all: &[u32]) -> Built<'a> {
    let theme = &app.theme;
    let header = Row::new(vec![Cell::from("ledger"), Cell::from("currency")]);
    let widths = vec![Constraint::Length(12), Constraint::Min(10)];
    let rows = visible
        .iter()
        .filter_map(|&i| all.get(i))
        .enumerate()
        .map(|(position, ledger)| {
            let currency = tbclient::currency(*ledger)
                .map(|c| format!("{} · {}", c.alpha, c.unit()))
                .unwrap_or_else(|| "not an ISO 4217 code".to_string());
            Row::new(vec![
                Cell::from(ledger.to_string()),
                Cell::from(currency).style(theme.hint),
            ])
            .style(stripe(theme, position))
        })
        .collect();
    (header, widths, rows)
}
