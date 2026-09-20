//! Every colour the UI can show, and the name it answers to in a theme file.
//!
//! The list is written once, in the `roles!` macro call below, which produces the enum, the array
//! index, the name table and the lookup together. A colour that has no name cannot be added to the
//! UI, because [`Palette`] has nowhere to put one.

use ratatui::style::Style;

macro_rules! roles {
    ($($variant:ident => $name:literal, $group:literal;)+) => {
        /// One themeable colour.
        #[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
        pub enum Role {
            $($variant,)+
        }

        impl Role {
            /// Every role, in the order a dumped theme file lists them.
            pub const ALL: &'static [Role] = &[$(Role::$variant,)+];

            /// The name used in a theme file.
            pub const fn name(self) -> &'static str {
                match self {
                    $(Role::$variant => $name,)+
                }
            }

            /// The heading a dumped theme file files this role under.
            pub const fn group(self) -> &'static str {
                match self {
                    $(Role::$variant => $group,)+
                }
            }

            /// The role a theme file names, or `None` if it names nothing we have.
            pub fn from_name(name: &str) -> Option<Self> {
                match name {
                    $($name => Some(Role::$variant),)+
                    _ => None,
                }
            }
        }
    };
}

roles! {
    Text => "text", "base";

    Border => "border", "chrome";
    BorderFocus => "border.focus", "chrome";
    Title => "title", "chrome";
    TitleScope => "title.scope", "chrome";
    TitleCount => "title.count", "chrome";
    Label => "label", "chrome";
    Value => "value", "chrome";
    Key => "key", "chrome";
    Hint => "hint", "chrome";
    Logo => "logo", "chrome";
    Badge => "badge", "chrome";

    TableHeader => "table.header", "table";
    TableCursor => "table.cursor", "table";
    TableStripe => "table.stripe", "table";
    TableId => "table.id", "table";
    TableNumber => "table.number", "table";

    Good => "good", "state";
    Warn => "warn", "state";
    Bad => "bad", "state";
    Busy => "busy", "state";

    FlagPending => "flag.pending", "flags";
    FlagPosted => "flag.posted", "flags";
    FlagVoided => "flag.voided", "flags";
    FlagClosed => "flag.closed", "flags";
    FlagLinked => "flag.linked", "flags";
    FlagHistory => "flag.history", "flags";
    FlagOther => "flag.other", "flags";

    StatusPosted => "status.posted", "verdict";
    StatusVoided => "status.voided", "verdict";
    StatusExpired => "status.expired", "verdict";
    StatusPending => "status.pending", "verdict";
    StatusUnknown => "status.unknown", "verdict";

    NetNegative => "net.negative", "amounts";
    NetPositive => "net.positive", "amounts";
}

impl Role {
    pub const COUNT: usize = Role::ALL.len();

    const fn index(self) -> usize {
        self as usize
    }
}

/// A style for every role. Missing roles are not representable: a palette always answers.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Palette([Style; Role::COUNT]);

impl Palette {
    /// A palette with nothing set, which renders as the terminal's own colours.
    pub fn blank() -> Self {
        Self([Style::new(); Role::COUNT])
    }

    pub fn set(&mut self, role: Role, style: Style) {
        self.0[role.index()] = style;
    }
}

impl std::ops::Index<Role> for Palette {
    type Output = Style;

    fn index(&self, role: Role) -> &Style {
        &self.0[role.index()]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_role_has_a_name_and_answers_to_it() {
        for &role in Role::ALL {
            assert_eq!(
                Role::from_name(role.name()),
                Some(role),
                "{} does not round trip",
                role.name()
            );
        }
    }

    #[test]
    fn no_two_roles_share_a_name() {
        let mut names: Vec<&str> = Role::ALL.iter().map(|role| role.name()).collect();
        names.sort_unstable();
        let count = names.len();
        names.dedup();
        assert_eq!(names.len(), count, "two roles answer to one name");
    }

    #[test]
    fn the_readme_documents_every_role() {
        // Roles are the public surface of a theme file. One added without a line in the table is
        // one nobody can discover, and the only place to look is the README.
        let readme = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../README.md");
        let text = std::fs::read_to_string(&readme)
            .unwrap_or_else(|error| panic!("reading {}: {error}", readme.display()));

        for &role in Role::ALL {
            assert!(
                text.contains(&format!("`{}`", role.name())),
                "{} is not in the README's role table",
                role.name()
            );
        }
    }

    #[test]
    fn a_role_indexes_its_own_slot() {
        let mut palette = Palette::blank();
        for &role in Role::ALL {
            palette.set(role, Style::new().fg(ratatui::style::Color::Indexed(7)));
            assert_eq!(
                palette[role].fg,
                Some(ratatui::style::Color::Indexed(7)),
                "{} reads back a different slot",
                role.name()
            );
        }
    }
}
