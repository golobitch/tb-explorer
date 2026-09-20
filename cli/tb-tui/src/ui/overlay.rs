//! The two panels that float over everything: `?` and `ctrl-a`.

use ratatui::Frame;
use ratatui::layout::{Constraint, Rect};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Clear, Paragraph};

use crate::app::{App, COMMANDS};

/// Every binding, in one place, so the help cannot drift from the keys.
pub const KEYS: &[(&str, &str)] = &[
    ("1 2 3", "accounts · transfers · ledgers"),
    ("j k ↓ ↑", "move"),
    ("g G", "first · last row"),
    ("enter", "open the selected row"),
    ("b", "balances, on an account"),
    ("esc", "back"),
    (":", "command — ask the cluster"),
    ("/", "filter — narrow what is shown"),
    ("ctrl-a", "list every command"),
    ("f", "amounts as currency"),
    (":theme", "colours — presets, or your own"),
    ("o", "newest first"),
    ("ctrl-r", "refresh"),
    ("a", "auto-refresh every 2s"),
    ("?", "this help"),
    ("q", "quit"),
];

pub fn help(frame: &mut Frame, area: Rect, app: &App) {
    let lines: Vec<Line> = KEYS
        .iter()
        .map(|(key, what)| {
            Line::from(vec![
                Span::styled(format!("  {key:<10}"), app.theme.key),
                Span::raw(*what),
            ])
        })
        .chain([
            Line::raw(""),
            Line::from(Span::styled(
                "  read-only: no create path in this binary",
                app.theme.hint,
            )),
        ])
        .collect();

    panel(frame, area, app, " keys ", lines, 52);
}

pub fn commands(frame: &mut Frame, area: Rect, app: &App) {
    let theme = &app.theme;
    let mut lines = vec![Line::from(vec![
        Span::styled(format!("  {:<16}", "command"), theme.label),
        Span::styled(format!("{:<12}", "aliases"), theme.label),
        Span::styled("what it opens", theme.label),
    ])];
    lines.extend(COMMANDS.iter().map(|(command, aliases, what)| {
        Line::from(vec![
            Span::styled(format!("  {command:<16}"), theme.key),
            Span::styled(format!("{aliases:<12}"), theme.hint),
            Span::raw(*what),
        ])
    }));

    panel(frame, area, app, " : commands ", lines, 66);
}

/// The theme list. The screen behind it is already wearing whatever is selected, so the list is
/// deliberately plain: the preview is the rest of the window, not a swatch in here.
pub fn themes(frame: &mut Frame, area: Rect, app: &App) {
    let theme = &app.theme;
    let Some(picker) = &app.themes else { return };

    let lines: Vec<Line> = picker
        .names
        .iter()
        .enumerate()
        .map(|(index, name)| {
            let selected = index == picker.index;
            let mark = if selected { "▌ " } else { "  " };
            let style = if selected { theme.key } else { theme.hint };
            Line::from(vec![Span::styled(format!("{mark}{name}"), style)])
        })
        .chain([
            Line::raw(""),
            Line::from(Span::styled(
                "  j k to look · enter keeps it · esc puts it back",
                theme.hint,
            )),
        ])
        .collect();

    panel(frame, area, app, " themes ", lines, 40);
}

fn panel(frame: &mut Frame, area: Rect, app: &App, title: &str, lines: Vec<Line>, width: u16) {
    let height = (lines.len() as u16 + 2).min(area.height.saturating_sub(2));
    let panel = area.centered(
        Constraint::Length(width.min(area.width.saturating_sub(4))),
        Constraint::Length(height),
    );

    frame.render_widget(Clear, panel);
    frame.render_widget(
        Paragraph::new(lines).block(
            Block::bordered()
                .border_type(BorderType::Rounded)
                .border_style(app.theme.border_focus)
                .title(Span::styled(title.to_string(), app.theme.title)),
        ),
        panel,
    );
}
