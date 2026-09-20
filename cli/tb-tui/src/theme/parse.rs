//! Reading and writing the theme file.
//!
//! One role per line, `role = fg [on bg] [modifiers]`, which is the whole grammar. It is parsed by
//! hand because the alternative is a serialisation stack for a file that is a list of pairs, and
//! tb-tui's dependency list is two crates deep on purpose.
//!
//! A file only has to name the roles it changes: parsing starts from a palette and overwrites what
//! the file mentions, so two lines is a valid theme.

use ratatui::style::{Color, Modifier, Style};

use super::role::{Palette, Role};

/// Where parsing gave up, and why. Carries the line so a hand-edited file can be fixed without
/// guessing which of forty lines is wrong.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ThemeError {
    pub source: String,
    pub line: usize,
    pub message: String,
}

impl std::fmt::Display for ThemeError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}:{}: {}", self.source, self.line, self.message)
    }
}

impl std::error::Error for ThemeError {}

/// Apply a theme file to `base`, which supplies every role the file leaves alone.
pub fn parse(text: &str, source: &str, base: Palette) -> Result<Palette, ThemeError> {
    let mut palette = base;

    for (index, raw) in text.lines().enumerate() {
        let line = index + 1;
        let fail = |message: String| ThemeError {
            source: source.to_string(),
            line,
            message,
        };

        let content = strip_comment(raw).trim();
        if content.is_empty() {
            continue;
        }

        let (name, value) = content
            .split_once('=')
            .ok_or_else(|| fail(format!("expected `role = colour`, found {content:?}")))?;
        let name = name.trim();

        let role = Role::from_name(name).ok_or_else(|| {
            let mut message = format!("unknown role {name:?}");
            if let Some(closest) = closest_role(name) {
                message.push_str(&format!(" — did you mean {:?}?", closest.name()));
            }
            fail(message)
        })?;

        palette.set(role, style(value.trim()).map_err(fail)?);
    }

    Ok(palette)
}

/// Print a palette as a theme file, grouped and aligned, ready to be edited.
pub fn dump(palette: &Palette) -> String {
    let width = Role::ALL
        .iter()
        .map(|role| role.name().len())
        .max()
        .unwrap_or(0);

    let mut out = String::new();
    let mut group = "";
    for &role in Role::ALL {
        if role.group() != group {
            group = role.group();
            out.push_str(&format!("\n# {group}\n"));
        }
        out.push_str(&format!(
            "{:width$} = {}\n",
            role.name(),
            describe(palette[role])
        ));
    }
    out
}

/// `#` is both the comment mark and the start of a colour, which is the one ambiguity in the
/// grammar. It is resolved by position: a line that begins with `#` is a comment whatever follows,
/// and anywhere else `#` only starts a comment when a space follows it. So `# nord` is a comment,
/// `#4c566a` is a colour, and a mistyped `#4c566` is reported as a bad colour rather than quietly
/// becoming a comment.
fn strip_comment(line: &str) -> &str {
    if line.trim_start().starts_with('#') {
        return "";
    }

    let bytes = line.as_bytes();
    let mut at = 0;
    while let Some(offset) = line[at..].find('#') {
        let hash = at + offset;
        match bytes.get(hash + 1) {
            None => return &line[..hash],
            Some(byte) if byte.is_ascii_whitespace() => return &line[..hash],
            Some(_) => at = hash + 1,
        }
    }
    line
}

fn style(value: &str) -> Result<Style, String> {
    let mut style = Style::new();
    let mut words = value.split_whitespace().peekable();

    if words.peek().is_none() {
        return Err("expected a colour, found nothing after `=`".to_string());
    }

    // A leading `on` means the line sets a background and leaves the foreground alone.
    if !matches!(words.peek(), Some(&"on")) {
        let word = words.next().expect("peeked");
        if let Some(colour) = colour(word)? {
            style = style.fg(colour);
        }
    }

    while let Some(word) = words.next() {
        match word {
            "on" => {
                let word = words
                    .next()
                    .ok_or_else(|| "expected a colour after `on`".to_string())?;
                if let Some(colour) = colour(word)? {
                    style = style.bg(colour);
                }
            }
            other => style = style.add_modifier(modifier(other)?),
        }
    }

    Ok(style)
}

fn modifier(word: &str) -> Result<Modifier, String> {
    Ok(match word {
        "bold" => Modifier::BOLD,
        "dim" => Modifier::DIM,
        "italic" => Modifier::ITALIC,
        "underline" | "underlined" => Modifier::UNDERLINED,
        "reverse" | "reversed" => Modifier::REVERSED,
        "crossed" | "strikethrough" => Modifier::CROSSED_OUT,
        other => {
            return Err(format!(
                "unknown modifier {other:?} — known: bold, dim, italic, underline, reverse, crossed"
            ));
        }
    })
}

/// `None` means "leave it to the terminal", which is what `default` spells.
fn colour(word: &str) -> Result<Option<Color>, String> {
    if word == "default" {
        return Ok(None);
    }

    if let Some(hex) = word.strip_prefix('#') {
        if hex.len() != 6 || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
            return Err(format!("{word:?} is not a colour — hex looks like #88c0d0"));
        }
        let channel = |at: usize| u8::from_str_radix(&hex[at..at + 2], 16).expect("hex digits");
        return Ok(Some(Color::Rgb(channel(0), channel(2), channel(4))));
    }

    if word.bytes().all(|byte| byte.is_ascii_digit()) {
        return word
            .parse::<u8>()
            .map(|index| Some(Color::Indexed(index)))
            .map_err(|_| format!("{word:?} is not a palette index — 0 to 255"));
    }

    Ok(Some(match word {
        "black" => Color::Black,
        "red" => Color::Red,
        "green" => Color::Green,
        "yellow" => Color::Yellow,
        "blue" => Color::Blue,
        "magenta" => Color::Magenta,
        "cyan" => Color::Cyan,
        "gray" | "grey" => Color::Gray,
        "dark_gray" | "dark_grey" => Color::DarkGray,
        "bright_red" | "light_red" => Color::LightRed,
        "bright_green" | "light_green" => Color::LightGreen,
        "bright_yellow" | "light_yellow" => Color::LightYellow,
        "bright_blue" | "light_blue" => Color::LightBlue,
        "bright_magenta" | "light_magenta" => Color::LightMagenta,
        "bright_cyan" | "light_cyan" => Color::LightCyan,
        "white" => Color::White,
        other => {
            return Err(format!(
                "unknown colour {other:?} — a name, #rrggbb, 0-255, or default"
            ));
        }
    }))
}

/// The inverse of [`style`], so a dumped file parses back to what it came from.
fn describe(style: Style) -> String {
    let mut parts = Vec::new();
    match style.fg {
        Some(colour) => parts.push(name_of(colour)),
        None => parts.push("default".to_string()),
    }
    if let Some(colour) = style.bg {
        parts.push("on".to_string());
        parts.push(name_of(colour));
    }
    for (modifier, name) in [
        (Modifier::BOLD, "bold"),
        (Modifier::DIM, "dim"),
        (Modifier::ITALIC, "italic"),
        (Modifier::UNDERLINED, "underline"),
        (Modifier::REVERSED, "reverse"),
        (Modifier::CROSSED_OUT, "crossed"),
    ] {
        if style.add_modifier.contains(modifier) {
            parts.push(name.to_string());
        }
    }
    parts.join(" ")
}

fn name_of(colour: Color) -> String {
    match colour {
        Color::Reset => "default".to_string(),
        Color::Black => "black".to_string(),
        Color::Red => "red".to_string(),
        Color::Green => "green".to_string(),
        Color::Yellow => "yellow".to_string(),
        Color::Blue => "blue".to_string(),
        Color::Magenta => "magenta".to_string(),
        Color::Cyan => "cyan".to_string(),
        Color::Gray => "gray".to_string(),
        Color::DarkGray => "dark_gray".to_string(),
        Color::LightRed => "bright_red".to_string(),
        Color::LightGreen => "bright_green".to_string(),
        Color::LightYellow => "bright_yellow".to_string(),
        Color::LightBlue => "bright_blue".to_string(),
        Color::LightMagenta => "bright_magenta".to_string(),
        Color::LightCyan => "bright_cyan".to_string(),
        Color::White => "white".to_string(),
        Color::Rgb(r, g, b) => format!("#{r:02x}{g:02x}{b:02x}"),
        Color::Indexed(index) => index.to_string(),
    }
}

/// The nearest role by edit distance, for the message after a typo. Anything further than a third
/// of the name away is not a suggestion, it is a distraction.
fn closest_role(typed: &str) -> Option<Role> {
    let (role, distance) = Role::ALL
        .iter()
        .map(|&role| (role, distance(typed, role.name())))
        .min_by_key(|&(_, distance)| distance)?;
    (distance * 3 <= typed.len().max(role.name().len())).then_some(role)
}

fn distance(left: &str, right: &str) -> usize {
    let right: Vec<char> = right.chars().collect();
    let mut row: Vec<usize> = (0..=right.len()).collect();

    for (i, a) in left.chars().enumerate() {
        let mut previous = row[0];
        row[0] = i + 1;
        for (j, &b) in right.iter().enumerate() {
            let cost = usize::from(a != b);
            let next = (row[j + 1] + 1).min(row[j] + 1).min(previous + cost);
            previous = row[j + 1];
            row[j + 1] = next;
        }
    }

    row[right.len()]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::{default_palette, monochrome_palette};

    fn parsed(text: &str) -> Result<Palette, ThemeError> {
        parse(text, "test.theme", Palette::blank())
    }

    #[test]
    fn a_line_sets_one_role() {
        let palette = parsed("border = #4c566a").unwrap();
        assert_eq!(palette[Role::Border].fg, Some(Color::Rgb(0x4c, 0x56, 0x6a)));
    }

    #[test]
    fn what_a_file_leaves_out_is_left_alone() {
        let palette = parse("border = red", "test.theme", default_palette()).unwrap();
        assert_eq!(palette[Role::Border].fg, Some(Color::Red));
        assert_eq!(
            palette[Role::Logo].fg,
            Some(Color::Cyan),
            "an untouched role kept its default"
        );
    }

    #[test]
    fn a_background_can_be_set_without_a_foreground() {
        let palette = parsed("table.stripe = on 235").unwrap();
        assert_eq!(palette[Role::TableStripe].fg, None);
        assert_eq!(palette[Role::TableStripe].bg, Some(Color::Indexed(235)));
    }

    #[test]
    fn colours_and_modifiers_read_together() {
        let palette = parsed("badge = black on green bold underline").unwrap();
        let style = palette[Role::Badge];
        assert_eq!(style.fg, Some(Color::Black));
        assert_eq!(style.bg, Some(Color::Green));
        assert!(style.add_modifier.contains(Modifier::BOLD));
        assert!(style.add_modifier.contains(Modifier::UNDERLINED));
    }

    #[test]
    fn default_means_whatever_the_terminal_says() {
        let palette = parsed("text = default bold").unwrap();
        assert_eq!(palette[Role::Text].fg, None);
        assert!(palette[Role::Text].add_modifier.contains(Modifier::BOLD));
    }

    #[test]
    fn comments_and_blank_lines_are_not_settings() {
        let palette = parsed("# a comment\n\n   \nborder = red\n").unwrap();
        assert_eq!(palette[Role::Border].fg, Some(Color::Red));
    }

    #[test]
    fn a_hash_with_no_space_is_still_a_whole_line_comment() {
        let palette = parsed("#nord, adapted\nborder = red").unwrap();
        assert_eq!(palette[Role::Border].fg, Some(Color::Red));
    }

    #[test]
    fn a_trailing_comment_does_not_eat_a_hex_colour() {
        let palette = parsed("border = #4c566a # the grey one").unwrap();
        assert_eq!(palette[Role::Border].fg, Some(Color::Rgb(0x4c, 0x56, 0x6a)));

        let palette = parsed("border = red # not #ff0000").unwrap();
        assert_eq!(palette[Role::Border].fg, Some(Color::Red));
    }

    #[test]
    fn every_failure_names_its_line() {
        let cases = [
            ("border red", "expected `role = colour`"),
            ("boarder = red", "unknown role"),
            ("border = mauve", "unknown colour"),
            ("border = #4c566", "not a colour"),
            ("border = red on", "after `on`"),
            ("border =", "found nothing"),
            ("border = red blinking", "unknown modifier"),
        ];
        for (text, expected) in cases {
            let error = parsed(&format!("# a comment\n{text}")).unwrap_err();
            assert_eq!(error.line, 2, "{text:?} reported the wrong line");
            assert!(
                error.message.contains(expected),
                "{text:?} said {:?}, which does not mention {expected:?}",
                error.message
            );
        }
    }

    #[test]
    fn a_typo_suggests_the_role_that_was_meant() {
        let error = parsed("boarder = red").unwrap_err();
        assert!(
            error.message.contains("\"border\""),
            "no suggestion in {:?}",
            error.message
        );

        let error = parsed("elephant = red").unwrap_err();
        assert!(
            !error.message.contains("did you mean"),
            "invented a suggestion: {:?}",
            error.message
        );
    }

    #[test]
    fn a_dumped_palette_parses_back_to_itself() {
        for palette in [default_palette(), monochrome_palette(), Palette::blank()] {
            let text = dump(&palette);
            let again = parse(&text, "dumped.theme", Palette::blank())
                .unwrap_or_else(|error| panic!("{error}\n{text}"));
            assert_eq!(again, palette, "round trip changed the palette:\n{text}");
        }
    }

    #[test]
    fn a_dump_names_every_role() {
        let text = dump(&default_palette());
        for &role in Role::ALL {
            assert!(
                text.lines().any(|line| line.starts_with(role.name())),
                "{} is missing from a dump",
                role.name()
            );
        }
    }
}
