//! The top band: what you are connected to, what the keys do, and a wordmark that doubles as a
//! status light — k9s's cheapest good idea.

use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Padding, Paragraph};

use crate::app::App;

/// Pure ASCII: a wordmark drawn from box characters would break wherever the font does.
const LOGO: [&str; 5] = [
    "######## ####",
    "   ##    ##  ##",
    "   ##    ######",
    "   ##    ##   ##",
    "   ##    ########",
];

/// The keys worth showing before someone presses `?`.
const PRIMARY: [(&str, &str); 8] = [
    ("1", "accounts"),
    ("2", "transfers"),
    ("3", "ledgers"),
    ("enter", "open"),
    (":", "command"),
    ("/", "filter"),
    ("?", "help"),
    ("q", "quit"),
];

pub fn draw(frame: &mut Frame, area: Rect, app: &App, compact: bool) {
    if compact {
        frame.render_widget(one_line(app), area);
        return;
    }

    let [context, keys, logo] = Layout::horizontal([
        Constraint::Length(34),
        Constraint::Min(24),
        // Wide enough for the wordmark plus the gap that keeps it off the frame.
        Constraint::Length(20),
    ])
    .areas(area);
    let logo = logo.inner(ratatui::layout::Margin {
        horizontal: 1,
        vertical: 0,
    });

    frame.render_widget(context_block(app), context);
    frame.render_widget(keys_block(app), keys);
    frame.render_widget(logo_block(app), logo);
}

/// On a short terminal the frame costs more rows than it earns.
fn one_line(app: &App) -> Paragraph<'_> {
    let theme = &app.theme;
    Paragraph::new(Line::from(vec![
        Span::styled("tb-tui ", theme.logo),
        Span::styled(
            format!("cluster {} · {} ", app.cluster_id, app.addresses),
            theme.hint,
        ),
        Span::styled(" READ-ONLY ", theme.badge),
    ]))
}

fn context_block(app: &App) -> Paragraph<'_> {
    let theme = &app.theme;
    let latency = app
        .latency
        .map(|l| format!("{:.1} ms", l.as_secs_f64() * 1000.0))
        .unwrap_or_else(|| "—".to_string());

    let rows = [
        ("cluster", app.cluster_id.to_string()),
        ("address", app.addresses.clone()),
        ("client", tbclient::CLIENT_VERSION.to_string()),
        ("latency", latency),
    ];
    let lines: Vec<Line> = rows
        .into_iter()
        .map(|(label, value)| {
            Line::from(vec![
                Span::styled(format!("{label:<9}"), theme.label),
                Span::styled(value, theme.value),
            ])
        })
        .collect();

    Paragraph::new(lines).block(framed(app, "context"))
}

fn keys_block(app: &App) -> Paragraph<'_> {
    let theme = &app.theme;
    // Column-major, two columns, so the eye runs down rather than across.
    let rows = PRIMARY.len().div_ceil(2);
    let lines: Vec<Line> = (0..rows)
        .map(|row| {
            let mut spans = Vec::new();
            for column in 0..2 {
                if let Some((key, what)) = PRIMARY.get(column * rows + row) {
                    // The key is padded as a unit so both columns line up whatever its length.
                    spans.push(Span::styled(
                        format!("{:<9}", format!("<{key}>")),
                        theme.key,
                    ));
                    spans.push(Span::styled(format!("{what:<12}"), theme.hint));
                }
            }
            Line::from(spans)
        })
        .collect();

    Paragraph::new(lines).block(framed(app, "keys"))
}

/// Tinted by state: busy while a query is in flight, red when the last one failed. A status light
/// that costs no rows.
fn logo_block(app: &App) -> Paragraph<'_> {
    let theme = &app.theme;
    let style = if app.error.is_some() {
        theme.bad
    } else if app.loading {
        theme.busy
    } else {
        theme.logo
    };

    let mut lines: Vec<Line> = LOGO
        .iter()
        .map(|row| Line::from(Span::styled(*row, style)))
        .collect();
    lines.push(Line::from(vec![
        Span::raw(" "),
        Span::styled(" READ-ONLY ", theme.badge),
    ]));
    Paragraph::new(lines)
}

fn framed<'a>(app: &App, title: &'a str) -> Block<'a> {
    Block::bordered()
        .border_type(BorderType::Rounded)
        .border_style(app.theme.border)
        .padding(Padding::horizontal(1))
        .title(Span::styled(format!(" {title} "), app.theme.label))
}
