//! A read-only terminal browser for TigerBeetle clusters.

mod app;
mod config;
#[cfg(test)]
mod tests;
mod theme;
mod ui;
mod worker;

use std::sync::Arc;
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use tbclient::Client;

use crate::app::{App, Mode, View};
use crate::theme::Theme;
use crate::worker::Worker;

struct Options {
    addresses: String,
    cluster_id: u128,
    /// Render one frame as text and exit, for scripts and CI: the terminal equivalent of the
    /// macOS app's snapshot hook, and the only way to check real data without a tty.
    dump: Option<String>,
    /// Colour off, for pipes, logs and terminals with their own ideas. `NO_COLOR` does the same.
    plain: bool,
    /// The size `--dump` renders at, so a narrow terminal can be checked without one.
    size: (u16, u16),
    /// A theme by name or by path. Overrides whatever the config file says.
    theme: Option<String>,
    /// Print a theme as a file and exit, which is how you start editing one.
    dump_theme: Option<Option<String>>,
    /// List what `--theme` accepts and exit.
    list_themes: bool,
}

fn parse_options() -> Result<Options, String> {
    let mut addresses = "127.0.0.1:3000".to_string();
    let mut cluster_id = 0u128;
    let mut dump = None;
    let mut plain = false;
    let mut size = (130u16, 20u16);
    let mut theme = None;
    let mut dump_theme = None;
    let mut list_themes = false;
    let mut args = std::env::args().skip(1).peekable();

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--addresses" | "-a" => {
                addresses = args.next().ok_or("--addresses needs a value")?;
            }
            "--cluster" | "-c" => {
                let raw = args.next().ok_or("--cluster needs a value")?;
                cluster_id = raw
                    .parse()
                    .map_err(|_| format!("{raw} is not a cluster id"))?;
            }
            "--no-color" => plain = true,
            "--size" => {
                let raw = args.next().ok_or("--size needs WxH")?;
                let (w, h) = raw.split_once('x').ok_or("--size looks like 80x24")?;
                size = (
                    w.parse().map_err(|_| "--size width")?,
                    h.parse().map_err(|_| "--size height")?,
                );
            }
            "--dump" => {
                dump = Some(args.next().unwrap_or_else(|| "accounts".to_string()));
            }
            "--theme" => {
                theme = Some(args.next().ok_or("--theme needs a name or a path")?);
            }
            "--dump-theme" => {
                // The name is optional, so only take the next argument when it is one.
                let named = args.peek().is_some_and(|next| !next.starts_with('-'));
                dump_theme = Some(named.then(|| args.next().expect("peeked")));
            }
            "--list-themes" => list_themes = true,
            "--help" | "-h" => {
                println!("{HELP}");
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument {other}")),
        }
    }
    Ok(Options {
        addresses,
        cluster_id,
        dump,
        plain,
        size,
        theme,
        dump_theme,
        list_themes,
    })
}

/// `--help` is the only documentation someone has in the moment, so it names every flag.
const HELP: &str = "\
tb-tui — a read-only terminal browser for TigerBeetle

  -a, --addresses <list>   replica addresses (default 127.0.0.1:3000)
  -c, --cluster <id>       cluster id (default 0)
      --theme <name|path>  colours, by preset name or theme file
      --list-themes        every theme this binary knows
      --dump-theme [name]  print a theme as a file, to edit and keep
      --no-color           no colour at all; NO_COLOR does the same
      --dump [view]        render one frame as text and exit
                           accounts|transfers|ledgers|help|account:1015|transfer:100539
      --size <WxH>         the size --dump renders at (default 130x20)
  -h, --help               this";

/// Colour off beats every theme: `NO_COLOR` is a promise, not a preference, so a theme can never
/// turn colour back on.
///
/// Everything else is a preference, and preferences have an order: the flag, then the environment,
/// then the config file, then the palette tb-tui ships with. The `Err` case is only for a theme
/// the user named on the command line — a broken config file is reported, not obeyed, because a
/// bad preference should never stand between you and a cluster.
fn resolve_theme(
    options: &Options,
    config: Option<&std::path::Path>,
) -> Result<(Theme, Option<String>), String> {
    if Theme::plain_wanted(options.plain) {
        return Ok((Theme::monochrome(), None));
    }

    if let Some(spec) = options
        .theme
        .clone()
        .or_else(|| std::env::var("TB_TUI_THEME").ok())
    {
        return Ok((Theme::from_palette(theme::resolve(&spec, config)?), None));
    }

    let Some(spec) = config.and_then(config::theme) else {
        return Ok((Theme::colourful(), None));
    };

    match theme::resolve(&spec, config) {
        Ok(palette) => Ok((Theme::from_palette(palette), None)),
        Err(message) => Ok((Theme::colourful(), Some(message))),
    }
}

fn main() {
    let options = match parse_options() {
        Ok(options) => options,
        Err(message) => {
            eprintln!("tb-tui: {message}");
            std::process::exit(2);
        }
    };

    // Everything about colour is answered before a socket is opened, so `--dump-theme` and
    // `--list-themes` work on a machine that has no cluster to reach.
    if options.list_themes {
        for preset in theme::preset::ALL {
            // The mark is the one thing worth saying: a hex theme is unreadable where truecolor
            // is not available, and ratatui will not downgrade it.
            let mark = if preset.truecolor {
                "  (truecolor)"
            } else {
                ""
            };
            println!("{}{mark}", preset.name);
        }
        return;
    }

    let config = config::directory();
    let (theme, complaint) = match resolve_theme(&options, config.as_deref()) {
        Ok(resolved) => resolved,
        Err(message) => {
            eprintln!("tb-tui: {message}");
            std::process::exit(2);
        }
    };

    if let Some(requested) = &options.dump_theme {
        let palette = match requested {
            Some(name) => match theme::resolve(name, config.as_deref()) {
                Ok(palette) => palette,
                Err(message) => {
                    eprintln!("tb-tui: {message}");
                    std::process::exit(2);
                }
            },
            None => theme.palette,
        };
        print!("{}", theme::parse::dump(&palette));
        return;
    }

    let client = match Client::connect(options.cluster_id, &options.addresses) {
        Ok(client) => Arc::new(client),
        Err(error) => {
            eprintln!("tb-tui: {error}");
            std::process::exit(1);
        }
    };

    let worker = Worker::spawn(Arc::clone(&client));
    let mut app = App::new(options.cluster_id, options.addresses.clone(), worker, theme);
    // A theme that would not load is worth saying out loud, but only once and only in the footer:
    // it is a preference, and you came here to read a cluster.
    app.status = complaint;
    app.config = config;

    if let Some(view) = options.dump {
        print!("{}", dump_frame(&mut app, &view, options.size));
        return;
    }

    let mut terminal = ratatui::init();
    let outcome = run(&mut terminal, &mut app);
    ratatui::restore();

    if let Err(error) = outcome {
        eprintln!("tb-tui: {error}");
        std::process::exit(1);
    }
}

/// k9s polls every two seconds; so does this, when asked to.
const AUTO_REFRESH: Duration = Duration::from_secs(2);

fn run(terminal: &mut ratatui::DefaultTerminal, app: &mut App) -> std::io::Result<()> {
    while !app.quit {
        app.drain();
        if app.should_auto_refresh(AUTO_REFRESH) {
            app.reload();
        }
        terminal.draw(|frame| ui::draw(frame, app))?;

        // A short poll keeps answers from the worker arriving promptly without spinning.
        if event::poll(Duration::from_millis(100))?
            && let Event::Key(key) = event::read()?
            && key.kind == KeyEventKind::Press
        {
            handle_key(app, key);
        }
    }
    Ok(())
}

/// Waits for the first answer, draws one frame into an off-screen buffer and returns it as text.
fn dump_frame(app: &mut App, view: &str, size: (u16, u16)) -> String {
    match view {
        "transfers" => app.show(View::Transfers),
        "ledgers" => app.show(View::Ledgers),
        "help" => app.toggle_help(),
        other if other.starts_with("account:") => {
            if let Ok(id) = other["account:".len()..].parse() {
                app.push(View::Account {
                    id,
                    balances: false,
                });
            }
        }
        other if other.starts_with("balances:") => {
            if let Ok(id) = other["balances:".len()..].parse() {
                app.push(View::Account { id, balances: true });
            }
        }
        other if other.starts_with("transfer:") => {
            if let Ok(id) = other["transfer:".len()..].parse() {
                app.push(View::Transfer { id });
            }
        }
        _ => {}
    }

    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    while app.loading && std::time::Instant::now() < deadline {
        app.drain();
        std::thread::sleep(Duration::from_millis(50));
    }
    app.drain();

    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(size.0, size.1))
        .expect("test backend");
    terminal.draw(|frame| ui::draw(frame, app)).expect("draw");
    let buffer = terminal.backend().buffer().clone();
    (0..buffer.area.height)
        .map(|y| {
            (0..buffer.area.width)
                .map(|x| buffer[(x, y)].symbol().to_string())
                .collect::<String>()
                .trim_end()
                .to_string()
        })
        .collect::<Vec<_>>()
        .join("\n")
        + "\n"
}

fn handle_key(app: &mut App, key: KeyEvent) {
    if key.modifiers.contains(KeyModifiers::CONTROL) {
        match key.code {
            KeyCode::Char('r') => app.reload(),
            KeyCode::Char('a') => app.show_commands(),
            KeyCode::Char('c') => app.quit = true,
            _ => {}
        }
        return;
    }

    // The theme list is modal: moving the selection repaints the screen, so the keys that move it
    // cannot also be doing their usual jobs underneath.
    if app.mode == Mode::Themes {
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') => app.cancel_themes(),
            KeyCode::Enter => app.keep_theme(),
            KeyCode::Char('j') | KeyCode::Down => app.move_theme(1),
            KeyCode::Char('k') | KeyCode::Up => app.move_theme(-1),
            _ => {}
        }
        return;
    }

    // While typing, every printable key belongs to the line being typed.
    if matches!(app.mode, Mode::Command | Mode::Filter) {
        match key.code {
            KeyCode::Esc => app.cancel_input(),
            KeyCode::Enter => app.submit_input(),
            KeyCode::Backspace => app.backspace(),
            KeyCode::Char(c) => app.type_char(c),
            _ => {}
        }
        return;
    }

    match key.code {
        KeyCode::Char(':') => app.begin_command(),
        KeyCode::Char('/') => app.begin_filter(),
        KeyCode::Char('q') => app.quit = true,
        KeyCode::Char('?') => app.toggle_help(),
        KeyCode::Esc => app.back(),
        KeyCode::Char('1') => app.show(View::Accounts),
        KeyCode::Char('2') => app.show(View::Transfers),
        KeyCode::Char('3') => app.show(View::Ledgers),
        KeyCode::Char('j') | KeyCode::Down => app.select_next(),
        KeyCode::Char('k') | KeyCode::Up => app.select_previous(),
        KeyCode::Char('g') | KeyCode::Home => app.select_first(),
        KeyCode::Char('G') | KeyCode::End => app.select_last(),
        KeyCode::Char('o') => app.toggle_order(),
        KeyCode::Enter => app.open_selection(),
        KeyCode::Char('b') => app.toggle_balances(),
        KeyCode::Char('a') => app.toggle_auto_refresh(),
        KeyCode::Char('f') => app.toggle_currency(),
        _ => {}
    }
}
