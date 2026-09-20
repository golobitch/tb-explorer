//! One palette, threaded through the render functions.
//!
//! The built-in default is made of **named ANSI colours** on purpose: ratatui does not downgrade
//! truecolor for terminals that cannot show it, and named colours inherit whatever scheme the
//! reader already chose for their terminal. The semantics match `FlagTag.tint` and `StatusBadge`
//! in the macOS app, so a pending transfer is orange in both windows. A theme file can replace any
//! of it — see [`role`] for the names, and the README for the file format.

pub mod parse;
pub mod preset;
pub mod role;

use ratatui::style::{Color, Modifier, Style};

pub use role::{Palette, Role};

/// Every theme that can be selected by name: the presets, plus whatever the user has put in
/// `~/.config/tb-tui/themes/`. A user theme with a preset's name appears once, and shadows it.
pub fn available(config: Option<&std::path::Path>) -> Vec<String> {
    let mut names: Vec<String> = preset::ALL
        .iter()
        .map(|preset| preset.name.to_string())
        .collect();

    let mut mine: Vec<String> = directory_themes(config);
    mine.sort();
    for name in mine {
        if !names.contains(&name) {
            names.push(name);
        }
    }
    names
}

fn directory_themes(config: Option<&std::path::Path>) -> Vec<String> {
    let Some(directory) = config else {
        return Vec::new();
    };
    let Ok(entries) = std::fs::read_dir(directory.join("themes")) else {
        return Vec::new(); // No themes of your own is the common case, not a problem.
    };

    entries
        .flatten()
        .map(|entry| entry.path())
        .filter(|path| {
            path.extension()
                .is_some_and(|extension| extension == "theme")
        })
        .filter_map(|path| {
            path.file_stem()
                .and_then(|stem| stem.to_str())
                .map(str::to_string)
        })
        .collect()
}

/// The palette a name or a path asks for. Anything with a separator or an extension is a file;
/// everything else is a name, so `nord` cannot accidentally mean the file `./nord`.
///
/// A preset starts from nothing rather than from the default palette: a preset that forgot a role
/// would otherwise show one stray cyan cell in an otherwise Nord screen. A file the user wrote
/// starts from the default, so a two-line theme is a valid theme.
pub fn resolve(spec: &str, config: Option<&std::path::Path>) -> Result<Palette, String> {
    // A theme of the user's own shadows a preset of the same name, so `nord` can be adjusted
    // without having to rename it to `nord-mine`.
    if let Some(directory) = config
        && let Some(path) = crate::config::user_theme(directory, spec)
    {
        return load(&path.to_string_lossy());
    }
    load(spec)
}

/// The palette a name or a path asks for, ignoring the user's themes directory.
pub fn load(spec: &str) -> Result<Palette, String> {
    if spec.contains('/') || spec.contains('.') {
        let text = std::fs::read_to_string(spec).map_err(|error| format!("{spec}: {error}"))?;
        return parse::parse(&text, spec, default_palette()).map_err(|error| error.to_string());
    }

    let preset = preset::find(spec).ok_or_else(|| {
        let names: Vec<&str> = preset::ALL.iter().map(|preset| preset.name).collect();
        format!("unknown theme {spec:?} — try one of: {}", names.join(", "))
    })?;

    parse::parse(preset.text, preset.name, Palette::blank()).map_err(|error| error.to_string())
}

#[derive(Clone, Copy, Debug)]
pub struct Theme {
    /// Every role, including the ones reached through [`Theme::flag`] and [`Theme::status`].
    pub palette: Palette,

    /// Painted over the whole frame before anything else, so text that carries no style of its own
    /// still belongs to the theme rather than to the terminal.
    pub text: Style,

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
    /// Whether colour is off, whatever theme was asked for. `NO_COLOR` is honoured here rather
    /// than at the terminal: set and non-empty means colour off, per no-color.org, and ratatui's
    /// crossterm backend does nothing about it on its own. A theme can never turn colour back on.
    pub fn plain_wanted(force_plain: bool) -> bool {
        force_plain || std::env::var_os("NO_COLOR").is_some_and(|value| !value.is_empty())
    }

    /// The theme a resolved palette describes.
    pub fn from_palette(palette: Palette) -> Self {
        Self {
            palette,
            text: palette[Role::Text],
            border: palette[Role::Border],
            border_focus: palette[Role::BorderFocus],
            title: palette[Role::Title],
            title_scope: palette[Role::TitleScope],
            title_count: palette[Role::TitleCount],
            label: palette[Role::Label],
            value: palette[Role::Value],
            key: palette[Role::Key],
            hint: palette[Role::Hint],
            logo: palette[Role::Logo],
            badge: palette[Role::Badge],
            header: palette[Role::TableHeader],
            cursor: palette[Role::TableCursor],
            stripe: palette[Role::TableStripe],
            id: palette[Role::TableId],
            number: palette[Role::TableNumber],
            good: palette[Role::Good],
            warn: palette[Role::Warn],
            bad: palette[Role::Bad],
            busy: palette[Role::Busy],
        }
    }

    pub fn colourful() -> Self {
        Self::from_palette(default_palette())
    }

    pub fn monochrome() -> Self {
        Self::from_palette(monochrome_palette())
    }

    /// The colour a flag carries in the macOS app. Anything unrecognised stays neutral rather than
    /// borrowing a meaning it does not have.
    pub fn flag(&self, name: &str) -> Style {
        self.palette[match name {
            "pending" => Role::FlagPending,
            "post_pending_transfer" => Role::FlagPosted,
            "void_pending_transfer" => Role::FlagVoided,
            "closed" => Role::FlagClosed,
            "linked" => Role::FlagLinked,
            "history" => Role::FlagHistory,
            _ => Role::FlagOther,
        }]
    }

    /// The verdict on a pending transfer, coloured as the app's StatusBadge colours it.
    pub fn status(&self, status: tbclient::PendingStatus) -> Style {
        use tbclient::PendingStatus::*;
        self.palette[match status {
            Posted => Role::StatusPosted,
            Voided => Role::StatusVoided,
            Expired => Role::StatusExpired,
            Pending => Role::StatusPending,
            Unknown => Role::StatusUnknown,
        }]
    }

    /// A net that is negative is worth noticing; one that is not is just a number.
    pub fn net(&self, negative: bool) -> Style {
        self.palette[if negative {
            Role::NetNegative
        } else {
            Role::NetPositive
        }]
    }
}

/// The colours tb-tui has always shipped with, now spelled as roles.
pub fn default_palette() -> Palette {
    let dim = Style::new().fg(Color::DarkGray);
    let mut palette = Palette::blank();
    let mut set = |role, style| palette.set(role, style);

    // Left unset: the terminal's own foreground and background, which is what makes the default
    // theme sit inside any colour scheme without arguing with it.
    set(Role::Text, Style::new());

    set(Role::Border, dim);
    set(Role::BorderFocus, Style::new().fg(Color::Cyan));
    set(
        Role::Title,
        Style::new().fg(Color::White).add_modifier(Modifier::BOLD),
    );
    set(Role::TitleScope, Style::new().fg(Color::Cyan));
    set(Role::TitleCount, dim);
    set(Role::Label, dim);
    set(Role::Value, Style::new().add_modifier(Modifier::BOLD));
    set(
        Role::Key,
        Style::new().fg(Color::Cyan).add_modifier(Modifier::BOLD),
    );
    set(Role::Hint, dim);
    set(Role::Logo, Style::new().fg(Color::Cyan));
    set(
        Role::Badge,
        Style::new()
            .fg(Color::Black)
            .bg(Color::Green)
            .add_modifier(Modifier::BOLD),
    );

    set(
        Role::TableHeader,
        Style::new().fg(Color::Cyan).add_modifier(Modifier::BOLD),
    );
    set(
        Role::TableCursor,
        Style::new().add_modifier(Modifier::REVERSED),
    );
    // One step off the background, the way ratatui's own table example shades rows.
    set(Role::TableStripe, Style::new().bg(Color::Indexed(235)));
    set(Role::TableId, Style::new().fg(Color::Gray));
    set(Role::TableNumber, Style::new());

    set(Role::Good, Style::new().fg(Color::Green));
    set(Role::Warn, Style::new().fg(Color::Yellow));
    set(Role::Bad, Style::new().fg(Color::Red));
    set(Role::Busy, Style::new().fg(Color::Yellow));

    set(Role::FlagPending, Style::new().fg(Color::Yellow));
    set(Role::FlagPosted, Style::new().fg(Color::Green));
    set(Role::FlagVoided, Style::new().fg(Color::Red));
    set(Role::FlagClosed, Style::new().fg(Color::Red));
    set(Role::FlagLinked, Style::new().fg(Color::Magenta));
    set(Role::FlagHistory, Style::new().fg(Color::Blue));
    set(Role::FlagOther, Style::new().fg(Color::DarkGray));

    set(Role::StatusPosted, Style::new().fg(Color::Green));
    set(Role::StatusVoided, Style::new().fg(Color::Red));
    set(Role::StatusExpired, Style::new().fg(Color::DarkGray));
    set(Role::StatusPending, Style::new().fg(Color::Yellow));
    set(Role::StatusUnknown, Style::new().fg(Color::Yellow));

    set(Role::NetNegative, Style::new().fg(Color::Red));
    set(Role::NetPositive, Style::new());

    palette
}

/// No colour at all: hierarchy from bold, dim and reverse, for `NO_COLOR` and for pipes.
pub fn monochrome_palette() -> Palette {
    let plain = Style::new();
    let bold = Style::new().add_modifier(Modifier::BOLD);
    let dim = Style::new().add_modifier(Modifier::DIM);
    let mut palette = Palette::blank();
    let mut set = |role, style| palette.set(role, style);

    set(Role::Text, plain);

    set(Role::Border, dim);
    set(Role::BorderFocus, bold);
    set(Role::Title, bold);
    set(Role::TitleScope, plain);
    set(Role::TitleCount, dim);
    set(Role::Label, dim);
    set(Role::Value, bold);
    set(Role::Key, bold);
    set(Role::Hint, dim);
    set(Role::Logo, plain);
    set(Role::Badge, Style::new().add_modifier(Modifier::REVERSED));

    set(Role::TableHeader, bold);
    set(
        Role::TableCursor,
        Style::new().add_modifier(Modifier::REVERSED),
    );
    set(Role::TableStripe, plain);
    set(Role::TableId, plain);
    set(Role::TableNumber, plain);

    set(Role::Good, plain);
    set(Role::Warn, bold);
    set(Role::Bad, bold);
    set(Role::Busy, dim);

    for role in [
        Role::FlagPending,
        Role::FlagPosted,
        Role::FlagVoided,
        Role::FlagClosed,
        Role::FlagLinked,
        Role::FlagHistory,
        Role::FlagOther,
    ] {
        set(role, plain);
    }

    // A verdict is the one thing worth a modifier when colour is gone: it is the answer you came
    // to the screen for.
    for role in [
        Role::StatusPosted,
        Role::StatusVoided,
        Role::StatusExpired,
        Role::StatusPending,
        Role::StatusUnknown,
    ] {
        set(role, bold);
    }

    set(Role::NetNegative, bold);
    set(Role::NetPositive, plain);

    palette
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn monochrome_uses_no_colour_at_all() {
        let theme = Theme::monochrome();
        for &role in Role::ALL {
            let style = theme.palette[role];
            assert_eq!(style.fg, None, "{} sets a foreground colour", role.name());
            assert_eq!(style.bg, None, "{} sets a background colour", role.name());
        }
    }

    #[test]
    fn flags_carry_the_colours_the_macos_app_gives_them() {
        let theme = Theme::colourful();
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
        let theme = Theme::colourful();
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

    #[test]
    fn a_verdict_still_stands_out_without_colour() {
        let theme = Theme::monochrome();
        for status in [
            tbclient::PendingStatus::Posted,
            tbclient::PendingStatus::Voided,
            tbclient::PendingStatus::Expired,
            tbclient::PendingStatus::Pending,
            tbclient::PendingStatus::Unknown,
        ] {
            assert!(
                theme.status(status).add_modifier.contains(Modifier::BOLD),
                "{status:?} is invisible without colour"
            );
        }
    }
}
