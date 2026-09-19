//! Drawing. Every function here takes `&App` and returns nothing — state changes live in `app`.
//!
//! Three bands, as k9s has them: a framed header of context, keys and a wordmark; the view itself;
//! and a crumb trail. Deliberately conservative about glyphs — no emoji, no arrows, nothing of
//! ambiguous width, because a character the terminal measures differently shifts everything after
//! it and breaks the frame.

mod detail;
mod header;
pub mod overlay;
mod table;

use ratatui::Frame;
use ratatui::layout::{Constraint, Layout};

use crate::app::{App, Mode, View};

/// Below this many rows — or this many columns — the framed header costs more than it tells you.
const COMPACT_HEIGHT: u16 = 20;
const COMPACT_WIDTH: u16 = 100;

pub fn draw(frame: &mut Frame, app: &App) {
    let compact = frame.area().height < COMPACT_HEIGHT || frame.area().width < COMPACT_WIDTH;
    let header_height = if compact { 1 } else { 7 };

    let [header, body, footer] = Layout::vertical([
        Constraint::Length(header_height),
        Constraint::Min(1),
        Constraint::Length(1),
    ])
    .areas(frame.area());

    header::draw(frame, header, app, compact);

    match app.view {
        View::Transfer { .. } | View::Account { .. } => detail::draw(frame, body, app),
        _ => table::draw(frame, body, app, table::title(app)),
    }

    footer::draw(frame, footer, app);

    match app.mode {
        Mode::Help => overlay::help(frame, frame.area(), app),
        Mode::Commands => overlay::commands(frame, frame.area(), app),
        _ => {}
    }
}

mod footer {
    use ratatui::Frame;
    use ratatui::layout::Rect;
    use ratatui::style::Modifier;
    use ratatui::text::{Line, Span};
    use ratatui::widgets::Paragraph;

    use crate::app::{App, Mode};

    /// k9s's crumb chips, and while typing, the command line.
    pub fn draw(frame: &mut Frame, area: Rect, app: &App) {
        if matches!(app.mode, Mode::Command | Mode::Filter) {
            frame.render_widget(prompt(app), area);
            return;
        }

        let theme = &app.theme;
        let mut spans = Vec::new();
        let crumbs = app.crumbs();
        for (i, crumb) in crumbs.iter().enumerate() {
            let last = i + 1 == crumbs.len();
            let style = if last {
                theme.key.add_modifier(Modifier::REVERSED)
            } else {
                theme.hint
            };
            spans.push(Span::styled(format!(" {crumb} "), style));
            spans.push(Span::raw(" "));
        }

        if !app.filter.is_empty() {
            spans.push(Span::styled(format!(" /{} ", app.filter), theme.warn));
            spans.push(Span::raw(" "));
        }
        if app.amounts.currency {
            spans.push(Span::styled(" currency ", theme.good));
            spans.push(Span::raw(" "));
        }
        if app.auto_refresh {
            spans.push(Span::styled(" auto 2s ", theme.good));
            spans.push(Span::raw(" "));
        }
        if let Some(status) = &app.status {
            spans.push(Span::styled(status.clone(), theme.warn));
        }

        frame.render_widget(Paragraph::new(Line::from(spans)), area);
    }

    fn prompt(app: &App) -> Paragraph<'_> {
        let theme = &app.theme;
        let (mark, style, hint) = match app.mode {
            Mode::Command => (
                ":",
                theme.key,
                "enter runs it · ctrl-a lists commands · esc cancels",
            ),
            _ => ("/", theme.warn, "filters the rows on screen · esc clears"),
        };
        Paragraph::new(Line::from(vec![
            Span::styled(mark, style),
            Span::raw(app.input.clone()),
            Span::styled("\u{2588}", style),
            Span::styled(format!("   {hint}"), theme.hint),
        ]))
    }
}
