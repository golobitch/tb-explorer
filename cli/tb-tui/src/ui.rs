//! Drawing. Every function here takes `&App` and returns nothing — state changes live in `app`.

use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, Paragraph, Row, Table, TableState};

use crate::app::{App, Mode, Rows, View};

pub const KEYS: &[(&str, &str)] = &[
    ("1", "accounts"),
    ("2", "transfers"),
    ("3", "ledgers"),
    ("j / k, ↓ / ↑", "move"),
    ("g / G", "first / last row"),
    ("o", "newest first"),
    ("ctrl-r", "refresh"),
    ("esc", "back"),
    ("?", "this help"),
    ("q", "quit"),
];

pub fn draw(frame: &mut Frame, app: &App) {
    let [header, body, footer] = Layout::vertical([
        Constraint::Length(2),
        Constraint::Min(1),
        Constraint::Length(1),
    ])
    .areas(frame.area());

    draw_header(frame, header, app);
    draw_body(frame, body, app);
    draw_footer(frame, footer, app);

    if app.mode == Mode::Help {
        draw_help(frame, frame.area());
    }
}

fn draw_header(frame: &mut Frame, area: Rect, app: &App) {
    let latency = app
        .latency
        .map(|l| format!("{:.1} ms", l.as_secs_f64() * 1000.0))
        .unwrap_or_else(|| "—".to_string());

    let first = Line::from(vec![
        Span::styled(
            "tb-tui ",
            Style::new().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        ),
        Span::raw(format!(
            "cluster {} · {} · client {} · {}",
            app.cluster_id,
            app.addresses,
            tbclient::CLIENT_VERSION,
            latency
        )),
        Span::raw("  "),
        // Read-only is a property of the binary, not a setting — say so where it is always visible.
        Span::styled(
            " READ-ONLY ",
            Style::new()
                .fg(Color::Black)
                .bg(Color::Green)
                .add_modifier(Modifier::BOLD),
        ),
    ]);

    let second = Line::from(vec![
        Span::styled(app.view.title(), Style::new().add_modifier(Modifier::BOLD)),
        Span::raw("  "),
        Span::styled(app.view.operation(), Style::new().fg(Color::DarkGray)),
        Span::raw("  "),
        Span::styled(
            if app.newest_first {
                "newest first"
            } else {
                "oldest first"
            },
            Style::new().fg(Color::DarkGray),
        ),
    ]);

    frame.render_widget(Paragraph::new(vec![first, second]), area);
}

fn draw_body(frame: &mut Frame, area: Rect, app: &App) {
    if let Some(error) = &app.error {
        let message = Paragraph::new(vec![
            Line::from(Span::styled(
                "Query failed",
                Style::new().fg(Color::Red).bold(),
            )),
            Line::raw(""),
            Line::raw(error.clone()),
            Line::raw(""),
            Line::styled(
                "ctrl-r retries · esc dismisses",
                Style::new().fg(Color::DarkGray),
            ),
        ]);
        frame.render_widget(message, area);
        return;
    }

    if app.rows.is_empty() {
        let text = if app.loading {
            "loading…"
        } else {
            "nothing here"
        };
        frame.render_widget(
            Paragraph::new(Span::styled(text, Style::new().fg(Color::DarkGray))),
            area,
        );
        return;
    }

    let mut state = TableState::default().with_selected(Some(app.selected));
    let highlight = Style::new().add_modifier(Modifier::REVERSED);

    match &app.rows {
        Rows::Accounts(rows) => {
            let widths = [
                Constraint::Length(20),
                Constraint::Length(8),
                Constraint::Length(6),
                Constraint::Length(18),
                Constraint::Length(18),
                Constraint::Length(18),
                Constraint::Min(10),
            ];
            let header = Row::new(vec![
                "id",
                "ledger",
                "code",
                "debits posted",
                "credits posted",
                "net",
                "flags",
            ])
            .style(Style::new().fg(Color::DarkGray));
            let body = rows.iter().map(|a| {
                let (net, negative) = a.net_posted();
                Row::new(vec![
                    a.id.to_string(),
                    a.ledger.to_string(),
                    a.code.to_string(),
                    a.debits_posted.to_string(),
                    a.credits_posted.to_string(),
                    if negative {
                        format!("-{net}")
                    } else {
                        net.to_string()
                    },
                    a.flag_names().join(" "),
                ])
            });
            frame.render_stateful_widget(
                Table::new(body, widths)
                    .header(header)
                    .row_highlight_style(highlight),
                area,
                &mut state,
            );
        }
        Rows::Transfers(rows) => {
            let widths = [
                Constraint::Length(20),
                Constraint::Length(18),
                Constraint::Length(18),
                Constraint::Length(18),
                Constraint::Length(8),
                Constraint::Length(6),
                Constraint::Min(10),
            ];
            let header = Row::new(vec![
                "id", "debit", "credit", "amount", "ledger", "code", "flags",
            ])
            .style(Style::new().fg(Color::DarkGray));
            let body = rows.iter().map(|t| {
                Row::new(vec![
                    t.id.to_string(),
                    t.debit_account_id.to_string(),
                    t.credit_account_id.to_string(),
                    t.amount.to_string(),
                    t.ledger.to_string(),
                    t.code.to_string(),
                    t.flag_names().join(" "),
                ])
            });
            frame.render_stateful_widget(
                Table::new(body, widths)
                    .header(header)
                    .row_highlight_style(highlight),
                area,
                &mut state,
            );
        }
        Rows::Balances(rows) => {
            let widths = [Constraint::Length(22); 5];
            let header = Row::new(vec![
                "timestamp",
                "debits pending",
                "debits posted",
                "credits pending",
                "credits posted",
            ])
            .style(Style::new().fg(Color::DarkGray));
            let body = rows.iter().map(|b| {
                Row::new(vec![
                    b.timestamp.to_string(),
                    b.debits_pending.to_string(),
                    b.debits_posted.to_string(),
                    b.credits_pending.to_string(),
                    b.credits_posted.to_string(),
                ])
            });
            frame.render_stateful_widget(
                Table::new(body, widths)
                    .header(header)
                    .row_highlight_style(highlight),
                area,
                &mut state,
            );
        }
        Rows::Ledgers(rows) => {
            let header = Row::new(vec!["ledger"]).style(Style::new().fg(Color::DarkGray));
            let body = rows.iter().map(|l| Row::new(vec![l.to_string()]));
            frame.render_stateful_widget(
                Table::new(body, [Constraint::Length(12)])
                    .header(header)
                    .row_highlight_style(highlight),
                area,
                &mut state,
            );
        }
        Rows::None => {}
    }
}

fn draw_footer(frame: &mut Frame, area: Rect, app: &App) {
    let count = app.rows.len();
    let noun = match app.view {
        View::Accounts => "accounts",
        View::Transfers => "transfers",
        View::Ledgers => "ledgers",
    };

    let mut spans = vec![
        Span::styled(app.breadcrumbs(), Style::new().fg(Color::Cyan)),
        Span::raw("  "),
        Span::raw(format!("{count} {noun}")),
    ];
    if app.loading {
        spans.push(Span::styled("  loading…", Style::new().fg(Color::Yellow)));
    }
    if let Some(status) = &app.status {
        spans.push(Span::raw("  "));
        spans.push(Span::styled(status.clone(), Style::new().fg(Color::Yellow)));
    }
    spans.push(Span::styled(
        "   <1> accounts <2> transfers <3> ledgers  ? help",
        Style::new().fg(Color::DarkGray),
    ));

    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

fn draw_help(frame: &mut Frame, area: Rect) {
    let width = 44u16.min(area.width.saturating_sub(4));
    let height = (KEYS.len() as u16 + 4).min(area.height.saturating_sub(2));
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    let panel = Rect {
        x,
        y,
        width,
        height,
    };

    let mut lines: Vec<Line> = KEYS
        .iter()
        .map(|(key, what)| {
            Line::from(vec![
                Span::styled(format!("  {key:<14}"), Style::new().fg(Color::Cyan)),
                Span::raw(*what),
            ])
        })
        .collect();
    lines.push(Line::raw(""));
    lines.push(Line::styled(
        "  read-only: no create path in this binary",
        Style::new().fg(Color::DarkGray),
    ));

    frame.render_widget(Clear, panel);
    frame.render_widget(
        Paragraph::new(lines).block(Block::default().borders(Borders::ALL).title(" keys ")),
        panel,
    );
}
