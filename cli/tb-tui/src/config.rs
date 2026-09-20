//! `~/.config/tb-tui/config` — the only file tb-tui writes, and it writes one key.
//!
//! The same `key = value` shape as a theme file, because two formats for two small files is one
//! format too many. Keys this version does not know are kept on rewrite rather than dropped: a
//! newer tb-tui's settings should survive an older one being run once.
//!
//! Everything here takes the directory as an argument. The environment is read in exactly one
//! place, [`directory`], which keeps the rest testable without setting environment variables —
//! unsound in a threaded test runner, and outright `unsafe` since edition 2024.

use std::path::{Path, PathBuf};

/// `$XDG_CONFIG_HOME/tb-tui`, else `~/.config/tb-tui` — on macOS too. The macOS app's Application
/// Support convention does not travel to the Linux builds this binary also ships for, and a
/// terminal tool living in `~/.config` is what everything else in the terminal does.
pub fn directory() -> Option<PathBuf> {
    let base = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(xdg) if !xdg.is_empty() => PathBuf::from(xdg),
        _ => PathBuf::from(std::env::var_os("HOME")?).join(".config"),
    };
    Some(base.join("tb-tui"))
}

fn file(directory: &Path) -> PathBuf {
    directory.join("config")
}

/// The theme the config names, if it names one. A missing or unreadable config is not an error:
/// it means "no preference", which is the same answer a fresh install gives.
pub fn theme(directory: &Path) -> Option<String> {
    let text = std::fs::read_to_string(file(directory)).ok()?;
    text.lines()
        .filter(|line| !line.trim_start().starts_with('#'))
        .filter_map(|line| line.split_once('='))
        .find(|(key, _)| key.trim() == "theme")
        .map(|(_, value)| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

/// A theme file the user put in `~/.config/tb-tui/themes/`, which shadows a preset of the same
/// name — otherwise a preset could never be adjusted without renaming it.
pub fn user_theme(directory: &Path, name: &str) -> Option<PathBuf> {
    let path = directory.join("themes").join(format!("{name}.theme"));
    path.is_file().then_some(path)
}

/// Write `theme = <name>`, keeping every other line and comment. Through a temporary file and a
/// rename, so an interrupted write cannot leave a half-truncated config behind.
pub fn set_theme(directory: &Path, name: &str) -> std::io::Result<()> {
    let path = file(directory);
    let existing = std::fs::read_to_string(&path).unwrap_or_default();

    let mut lines: Vec<String> = Vec::new();
    let mut replaced = false;
    for line in existing.lines() {
        let is_theme = !line.trim_start().starts_with('#')
            && line
                .split_once('=')
                .is_some_and(|(key, _)| key.trim() == "theme");
        if is_theme && !replaced {
            lines.push(format!("theme = {name}"));
            replaced = true;
        } else if !is_theme {
            lines.push(line.to_string());
        }
    }
    if !replaced {
        if !lines.is_empty() && !lines.last().is_some_and(|line| line.trim().is_empty()) {
            lines.push(String::new());
        }
        lines.push(format!("theme = {name}"));
    }

    std::fs::create_dir_all(directory)?;
    let temporary = path.with_extension("tmp");
    std::fs::write(&temporary, lines.join("\n") + "\n")?;
    std::fs::rename(&temporary, &path)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A directory of our own, without pulling in a crate to make one.
    struct Scratch(PathBuf);

    impl Scratch {
        fn new(name: &str) -> Self {
            let path = std::env::temp_dir().join(format!("tb-tui-{name}-{}", std::process::id()));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        fn write(&self, name: &str, text: &str) {
            std::fs::create_dir_all(self.0.join(name).parent().unwrap()).unwrap();
            std::fs::write(self.0.join(name), text).unwrap();
        }

        fn read(&self, name: &str) -> String {
            std::fs::read_to_string(self.0.join(name)).unwrap()
        }
    }

    impl Drop for Scratch {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn no_config_is_not_an_error() {
        let scratch = Scratch::new("absent");
        assert_eq!(theme(&scratch.0), None);
    }

    #[test]
    fn the_theme_is_read_past_comments_and_blank_lines() {
        let scratch = Scratch::new("read");
        scratch.write("config", "# mine\n\n  theme =  nord  \n");
        assert_eq!(theme(&scratch.0).as_deref(), Some("nord"));
    }

    #[test]
    fn a_commented_out_theme_is_no_theme() {
        let scratch = Scratch::new("commented");
        scratch.write("config", "# theme = nord\n");
        assert_eq!(theme(&scratch.0), None);
    }

    #[test]
    fn writing_a_theme_keeps_everything_else() {
        let scratch = Scratch::new("write");
        scratch.write("config", "# my config\ntheme = nord\nsomething = else\n");

        set_theme(&scratch.0, "dracula").unwrap();

        let written = scratch.read("config");
        assert_eq!(theme(&scratch.0).as_deref(), Some("dracula"));
        assert!(
            written.contains("# my config"),
            "lost a comment:\n{written}"
        );
        assert!(
            written.contains("something = else"),
            "lost a key this version does not know:\n{written}"
        );
        assert_eq!(
            written.matches("theme =").count(),
            1,
            "left two theme lines:\n{written}"
        );
    }

    #[test]
    fn writing_into_nothing_makes_the_file_and_its_directory() {
        let scratch = Scratch::new("fresh");
        let nested = scratch.0.join("deeper");
        set_theme(&nested, "nord").unwrap();
        assert_eq!(theme(&nested).as_deref(), Some("nord"));
        assert!(
            !nested.join("config.tmp").exists(),
            "left the temporary file behind"
        );
    }

    #[test]
    fn a_user_theme_is_found_by_name_and_only_when_it_exists() {
        let scratch = Scratch::new("themes");
        scratch.write("themes/mine.theme", "border = red\n");
        assert!(user_theme(&scratch.0, "mine").is_some());
        assert!(user_theme(&scratch.0, "nord").is_none());
    }
}
