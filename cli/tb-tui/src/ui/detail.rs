//! Detail views: a pane of fields above the table that belongs to them.
//!
//! A transfer is not a row in a list of transfers — it is a thing with a verdict, two accounts and
//! a chain. The layout says so.

use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Padding, Paragraph};

use crate::app::{App, View};
use crate::ui::table::{self, Title};

pub fn draw(frame: &mut Frame, area: Rect, app: &App) {
    let fields = match app.view {
        View::Transfer { .. } => transfer_fields(app),
        View::Account { .. } => account_fields(app),
        _ => Vec::new(),
    };

    // The fields are the point of a detail view, so they get the room they need; the table keeps
    // a floor of a border, a header, one row and its counter.
    let wanted = fields.len() as u16 + 2;
    let height = wanted.min(area.height.saturating_sub(5)).max(3);
    let [top, bottom] =
        Layout::vertical([Constraint::Length(height), Constraint::Min(3)]).areas(area);

    frame.render_widget(
        Paragraph::new(fields).block(
            Block::bordered()
                .border_type(BorderType::Rounded)
                .border_style(app.theme.border)
                .padding(Padding::horizontal(1))
                .title(Span::styled(
                    format!(" {} ", app.view.title()),
                    app.theme.label,
                )),
        ),
        top,
    );

    table::draw(frame, bottom, app, table_title(app));
}

fn table_title(app: &App) -> Title {
    match app.view {
        View::Transfer { .. } => Title {
            name: "chain".to_string(),
            scope: Some(app.view.operation().to_string()),
        },
        View::Account { balances: true, .. } => Title {
            name: "balances".to_string(),
            scope: Some(app.view.operation().to_string()),
        },
        _ => Title {
            name: "transfers".to_string(),
            scope: Some(app.view.operation().to_string()),
        },
    }
}

fn field<'a>(app: &App, label: &'a str, value: Vec<Span<'a>>) -> Line<'a> {
    let mut spans = vec![Span::styled(format!("{label:<16}"), app.theme.label)];
    spans.extend(value);
    Line::from(spans)
}

fn transfer_fields<'a>(app: &App) -> Vec<Line<'a>> {
    let theme = &app.theme;
    let Some(chain) = &app.chain else {
        return vec![Line::from(Span::styled("loading…", theme.hint))];
    };
    let transfer = chain.transfer;

    let verdict = chain.resolution.as_ref().map(|resolution| {
        let mut spans = vec![Span::styled(
            format!(" {} ", resolution.status.label()),
            theme.status(resolution.status),
        )];
        if resolution.status == tbclient::PendingStatus::Unknown {
            spans.push(Span::styled(
                format!("  scanned {} later debits", resolution.scanned),
                theme.hint,
            ));
        }
        if let Some(expires) = resolution.expires_at {
            spans.push(Span::styled(format!("  expires {expires}"), theme.hint));
        }
        spans
    });

    let mut lines = vec![
        field(
            app,
            "id",
            vec![Span::styled(transfer.id.to_string(), theme.value)],
        ),
        field(
            app,
            "debit → credit",
            vec![
                Span::styled(transfer.debit_account_id.to_string(), theme.value),
                Span::styled("  →  ", theme.hint),
                Span::styled(transfer.credit_account_id.to_string(), theme.value),
            ],
        ),
        field(
            app,
            "amount",
            vec![Span::styled(
                app.amounts.amount(transfer.amount, transfer.ledger),
                theme.value,
            )],
        ),
        field(
            app,
            "pending",
            verdict.unwrap_or_else(|| vec![Span::styled("not a pending transfer", theme.hint)]),
        ),
        field(
            app,
            "ledger · code",
            vec![Span::raw(format!(
                "{} · {}",
                app.amounts.ledger(transfer.ledger),
                transfer.code
            ))],
        ),
        field(
            app,
            "flags",
            transfer
                .flag_names()
                .iter()
                .flat_map(|name| [Span::styled(name.clone(), theme.flag(name)), Span::raw(" ")])
                .collect::<Vec<_>>(),
        ),
        field(
            app,
            "timestamp",
            vec![Span::styled(transfer.timestamp.to_string(), theme.hint)],
        ),
    ];

    if transfer.pending_id != 0 {
        lines.push(field(
            app,
            "resolves",
            vec![Span::styled(transfer.pending_id.to_string(), theme.id)],
        ));
    }

    lines
}

fn account_fields<'a>(app: &App) -> Vec<Line<'a>> {
    let theme = &app.theme;
    let Some(account) = app.account else {
        return vec![Line::from(Span::styled("loading…", theme.hint))];
    };
    let (net, negative) = account.net_posted();

    vec![
        field(
            app,
            "id",
            vec![Span::styled(account.id.to_string(), theme.value)],
        ),
        field(
            app,
            "ledger · code",
            vec![Span::raw(format!(
                "{} · {}",
                app.amounts.ledger(account.ledger),
                account.code
            ))],
        ),
        field(
            app,
            "debits",
            vec![
                Span::styled(
                    app.amounts.amount(account.debits_posted, account.ledger),
                    theme.value,
                ),
                Span::styled("  posted     ", theme.hint),
                Span::raw(app.amounts.amount(account.debits_pending, account.ledger)),
                Span::styled("  pending", theme.hint),
            ],
        ),
        field(
            app,
            "credits",
            vec![
                Span::styled(
                    app.amounts.amount(account.credits_posted, account.ledger),
                    theme.value,
                ),
                Span::styled("  posted     ", theme.hint),
                Span::raw(app.amounts.amount(account.credits_pending, account.ledger)),
                Span::styled("  pending", theme.hint),
            ],
        ),
        field(
            app,
            "net",
            vec![Span::styled(
                app.amounts.signed(net, negative, account.ledger),
                theme.net(negative),
            )],
        ),
        field(
            app,
            "flags",
            account
                .flag_names()
                .iter()
                .flat_map(|name| [Span::styled(name.clone(), theme.flag(name)), Span::raw(" ")])
                .collect::<Vec<_>>(),
        ),
    ]
}
