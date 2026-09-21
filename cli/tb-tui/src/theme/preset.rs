//! The themes compiled into the binary.
//!
//! Each one is a real theme file under `cli/tb-tui/themes/`, parsed at startup by the same parser
//! a hand-written theme goes through. So a preset is also a worked example of the format, and a
//! preset with a typo in it fails the test suite rather than someone's terminal.

/// Name, file, and whether it names hex colours — which a terminal without truecolor cannot show.
pub struct Preset {
    pub name: &'static str,
    pub text: &'static str,
    pub truecolor: bool,
}

macro_rules! presets {
    ($(($name:literal, $file:literal, $truecolor:literal)),+ $(,)?) => {
        pub const ALL: &[Preset] = &[
            $(Preset {
                name: $name,
                text: include_str!(concat!("../../themes/", $file)),
                truecolor: $truecolor,
            },)+
        ];
    };
}

presets! {
    // The two that inherit the terminal's own scheme come first: they are the ones that work
    // everywhere, and the default is the first line someone reads.
    ("ansi", "ansi.theme", false),
    ("mono", "mono.theme", false),
    ("andromeda", "andromeda.theme", true),
    ("catppuccin-mocha", "catppuccin-mocha.theme", true),
    ("dracula", "dracula.theme", true),
    ("gruvbox-dark", "gruvbox-dark.theme", true),
    ("nord", "nord.theme", true),
    ("one-dark", "one-dark.theme", true),
    ("solarized-dark", "solarized-dark.theme", true),
    ("tokyo-night", "tokyo-night.theme", true),
}

pub fn find(name: &str) -> Option<&'static Preset> {
    ALL.iter().find(|preset| preset.name == name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::parse::parse;
    use crate::theme::role::{Palette, Role};
    use crate::theme::{default_palette, monochrome_palette};

    #[test]
    fn every_preset_parses() {
        for preset in ALL {
            parse(preset.text, preset.name, Palette::blank())
                .unwrap_or_else(|error| panic!("{}: {error}", preset.name));
        }
    }

    #[test]
    fn a_preset_sets_every_role_it_knows_about() {
        // A preset that forgets a role would inherit it from the default palette, which is how a
        // Nord screen ends up with one cyan cell in it.
        for preset in ALL {
            let from_blank = parse(preset.text, preset.name, Palette::blank()).unwrap();
            let from_default = parse(preset.text, preset.name, default_palette()).unwrap();
            for &role in Role::ALL {
                assert_eq!(
                    from_blank[role],
                    from_default[role],
                    "{} never sets {}",
                    preset.name,
                    role.name()
                );
            }
        }
    }

    #[test]
    fn the_shipped_files_match_the_built_in_palettes() {
        let ansi = parse(find("ansi").unwrap().text, "ansi", Palette::blank()).unwrap();
        assert_eq!(ansi, default_palette(), "ansi.theme has drifted");

        let mono = parse(find("mono").unwrap().text, "mono", Palette::blank()).unwrap();
        assert_eq!(mono, monochrome_palette(), "mono.theme has drifted");
    }

    #[test]
    fn a_truecolor_preset_is_marked_as_one() {
        for preset in ALL {
            let hex = preset
                .text
                .lines()
                .filter(|line| !line.trim_start().starts_with('#'))
                .any(|line| line.contains('#'));
            assert_eq!(
                hex,
                preset.truecolor,
                "{} is marked truecolor={} but {} hex colours",
                preset.name,
                preset.truecolor,
                if hex { "uses" } else { "uses no" }
            );
        }
    }

    /// WCAG relative luminance, which is the only defensible way to say "too faint to read".
    fn luminance(colour: ratatui::style::Color) -> Option<f64> {
        let ratatui::style::Color::Rgb(r, g, b) = colour else {
            return None; // A named colour is whatever the terminal says it is.
        };
        let channel = |value: u8| {
            let value = f64::from(value) / 255.0;
            if value <= 0.03928 {
                value / 12.92
            } else {
                ((value + 0.055) / 1.055).powf(2.4)
            }
        };
        Some(0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b))
    }

    #[test]
    fn every_preset_is_readable_against_its_own_background() {
        // A hint nobody can read is not a hint. Borders are rules rather than words, and the
        // cursor and badge carry their own background, so they set their own contrast.
        const EXEMPT: &[Role] = &[
            Role::Border,
            Role::BorderFocus,
            Role::TableStripe,
            Role::TableCursor,
            Role::Badge,
        ];
        const FLOOR: f64 = 3.0;

        for preset in ALL {
            let palette = parse(preset.text, preset.name, Palette::blank()).unwrap();
            let Some(background) = palette[Role::Text].bg.and_then(luminance) else {
                continue; // ansi and mono defer to the terminal, which we cannot measure.
            };

            for &role in Role::ALL {
                if EXEMPT.contains(&role) {
                    continue;
                }
                let Some(foreground) = palette[role].fg.and_then(luminance) else {
                    continue;
                };
                let (lighter, darker) = if foreground > background {
                    (foreground, background)
                } else {
                    (background, foreground)
                };
                let ratio = (lighter + 0.05) / (darker + 0.05);
                assert!(
                    ratio >= FLOOR,
                    "{} {} is {ratio:.2}:1 against its own background, below {FLOOR}:1",
                    preset.name,
                    role.name()
                );
            }
        }
    }

    #[test]
    fn every_file_in_the_themes_directory_is_registered() {
        // Dropping a file in and forgetting the table would ship a theme nobody can select.
        let directory = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("themes");
        for entry in std::fs::read_dir(&directory).expect("themes/ is readable") {
            let path = entry.expect("a directory entry").path();
            let name = path
                .file_stem()
                .and_then(|stem| stem.to_str())
                .expect("a file name");
            assert!(
                find(name).is_some(),
                "themes/{}.theme is not in the preset table",
                name
            );
        }
        assert_eq!(
            std::fs::read_dir(&directory).unwrap().count(),
            ALL.len(),
            "the table and the directory disagree"
        );
    }
}
