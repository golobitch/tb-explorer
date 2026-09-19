//! One palette, threaded through the render functions.
//!
//! Built from **named ANSI colours** rather than RGB on purpose: ratatui does not downgrade
//! truecolor for terminals that cannot show it, and named colours inherit whatever scheme the
//! reader already chose for their terminal. The semantics match `FlagTag.tint` and `StatusBadge`
//! in the macOS app, so a pending transfer is orange in both windows.

use ratatui::style::{Color, Modifier, Style};

#[derive(Clone, Copy, Debug)]
pub struct Theme {
    /// True when colour is off entirely; hierarchy then comes from bold, dim and reverse.
    pub monochrome: bool,

    pub border: Style,
    pub border_focus: Style,
    pub title: Style,
    pub title_scope: Style,
    pub title_count: Style,

    pub label: Style,
    pub value: Style,
    pub key: Style,
    pub hint: Style,
    pub logo: Style,
    pub badge: Style,

    pub header: Style,
    pub cursor: Style,
    pub stripe: Style,
    pub id: Style,
    pub number: Style,

    pub good: Style,
    pub warn: Style,
    pub bad: Style,
    pub busy: Style,
}

impl Theme {
    /// `NO_COLOR` is honoured here rather than at the terminal: set and non-empty means colour off,
    /// per no-color.org, and ratatui's crossterm backend does nothing about it on its own.
    pub fn detect(force_plain: bool) -> Self {
        let no_color = std::env::var_os("NO_COLOR").is_some_and(|value| !value.is_empty());
        if force_plain || no_color {
            Self::monochrome()
        } else {
            Self::colourful()
        }
    }

    fn colourful() -> Self {
        let dim = Style::new().fg(Color::DarkGray);
        Self {
            monochrome: false,
            border: dim,
            border_focus: Style::new().fg(Color::Cyan),
            title: Style::new().fg(Color::White).add_modifier(Modifier::BOLD),
            title_scope: Style::new().fg(Color::Cyan),
            title_count: dim,
            label: dim,
            value: Style::new().add_modifier(Modifier::BOLD),
            key: Style::new().fg(Color::Cyan).add_modifier(Modifier::BOLD),
            hint: dim,
            logo: Style::new().fg(Color::Cyan),
            badge: Style::new()
                .fg(Color::Black)
                .bg(Color::Green)
                .add_modifier(Modifier::BOLD),
            header: Style::new().fg(Color::Cyan).add_modifier(Modifier::BOLD),
            cursor: Style::new().add_modifier(Modifier::REVERSED),
            // One step off the background, the way ratatui's own table example shades rows.
            stripe: Style::new().bg(Color::Indexed(235)),
            id: Style::new().fg(Color::Gray),
            number: Style::new(),
            good: Style::new().fg(Color::Green),
            warn: Style::new().fg(Color::Yellow),
            bad: Style::new().fg(Color::Red),
            busy: Style::new().fg(Color::Yellow),
        }
    }

    fn monochrome() -> Self {
        let plain = Style::new();
        let dim = Style::new().add_modifier(Modifier::DIM);
        Self {
            monochrome: true,
            border: dim,
            border_focus: Style::new().add_modifier(Modifier::BOLD),
            title: Style::new().add_modifier(Modifier::BOLD),
            title_scope: plain,
            title_count: dim,
            label: dim,
            value: Style::new().add_modifier(Modifier::BOLD),
            key: Style::new().add_modifier(Modifier::BOLD),
            hint: dim,
            logo: plain,
            badge: Style::new().add_modifier(Modifier::REVERSED),
            header: Style::new().add_modifier(Modifier::BOLD),
            cursor: Style::new().add_modifier(Modifier::REVERSED),
            stripe: plain,
            id: plain,
            number: plain,
            good: plain,
            warn: Style::new().add_modifier(Modifier::BOLD),
            bad: Style::new().add_modifier(Modifier::BOLD),
            busy: dim,
        }
    }

    /// The colour a flag carries in the macOS app. Anything unrecognised stays neutral rather than
    /// borrowing a meaning it does not have.
    pub fn flag(&self, name: &str) -> Style {
        if self.monochrome {
            return Style::new();
        }
        match name {
            "pending" => Style::new().fg(Color::Yellow),
            "post_pending_transfer" => Style::new().fg(Color::Green),
            "void_pending_transfer" | "closed" => Style::new().fg(Color::Red),
            "linked" => Style::new().fg(Color::Magenta),
            "history" => Style::new().fg(Color::Blue),
            _ => Style::new().fg(Color::DarkGray),
        }
    }

    /// The verdict on a pending transfer, coloured as the app's StatusBadge colours it.
    pub fn status(&self, status: tbclient::PendingStatus) -> Style {
        use tbclient::PendingStatus::*;
        if self.monochrome {
            return Style::new().add_modifier(Modifier::BOLD);
        }
        match status {
            Posted => self.good,
            Voided => self.bad,
            Expired => Style::new().fg(Color::DarkGray),
            Pending => Style::new().fg(Color::Yellow),
            Unknown => self.warn,
        }
    }

    /// A net that is negative is worth noticing; one that is not is just a number.
    pub fn net(&self, negative: bool) -> Style {
        if negative { self.bad } else { self.number }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn monochrome_uses_no_colour_at_all() {
        let theme = Theme::detect(true);
        for style in [
            theme.border,
            theme.title,
            theme.key,
            theme.badge,
            theme.cursor,
            theme.good,
            theme.bad,
            theme.flag("pending"),
            theme.status(tbclient::PendingStatus::Posted),
        ] {
            assert_eq!(style.fg, None, "{style:?} sets a foreground colour");
            assert_eq!(style.bg, None, "{style:?} sets a background colour");
        }
    }

    #[test]
    fn flags_carry_the_colours_the_macos_app_gives_them() {
        let theme = Theme::detect(false);
        assert_eq!(theme.flag("pending").fg, Some(Color::Yellow));
        assert_eq!(theme.flag("post_pending_transfer").fg, Some(Color::Green));
        assert_eq!(theme.flag("void_pending_transfer").fg, Some(Color::Red));
        assert_eq!(theme.flag("closed").fg, Some(Color::Red));
        assert_eq!(theme.flag("linked").fg, Some(Color::Magenta));
        assert_eq!(theme.flag("history").fg, Some(Color::Blue));
        assert_eq!(
            theme.flag("imported").fg,
            Some(Color::DarkGray),
            "an unrecognised flag borrows no meaning"
        );
    }

    #[test]
    fn a_verdict_reads_at_a_glance() {
        let theme = Theme::detect(false);
        assert_eq!(
            theme.status(tbclient::PendingStatus::Posted).fg,
            Some(Color::Green)
        );
        assert_eq!(
            theme.status(tbclient::PendingStatus::Voided).fg,
            Some(Color::Red)
        );
        assert_eq!(
            theme.status(tbclient::PendingStatus::Unknown).fg,
            Some(Color::Yellow)
        );
        assert_eq!(theme.net(true).fg, Some(Color::Red));
        assert_eq!(theme.net(false).fg, None);
    }
}
