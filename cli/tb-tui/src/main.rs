//! A read-only terminal browser for TigerBeetle clusters.

mod app;
#[cfg(test)]
mod tests;
mod ui;
mod worker;

use std::sync::Arc;
use std::time::Duration;

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use tbclient::Client;

use crate::app::{App, View};
use crate::worker::Worker;

struct Options {
    addresses: String,
    cluster_id: u128,
    /// Render one frame as text and exit, for scripts and CI: the terminal equivalent of the
    /// macOS app's snapshot hook, and the only way to check real data without a tty.
    dump: Option<String>,
}

fn parse_options() -> Result<Options, String> {
    let mut addresses = "127.0.0.1:3000".to_string();
    let mut cluster_id = 0u128;
    let mut dump = None;
    let mut args = std::env::args().skip(1);

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
            "--dump" => {
                dump = Some(args.next().unwrap_or_else(|| "accounts".to_string()));
            }
            "--help" | "-h" => {
                println!(
                    "tb-tui [--addresses 127.0.0.1:3000] [--cluster 0] [--dump accounts|transfers|ledgers|help]"
                );
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument {other}")),
        }
    }
    Ok(Options {
        addresses,
        cluster_id,
        dump,
    })
}

fn main() {
    let options = match parse_options() {
        Ok(options) => options,
        Err(message) => {
            eprintln!("tb-tui: {message}");
            std::process::exit(2);
        }
    };

    let client = match Client::connect(options.cluster_id, &options.addresses) {
        Ok(client) => Arc::new(client),
        Err(error) => {
            eprintln!("tb-tui: {error}");
            std::process::exit(1);
        }
    };

    let worker = Worker::spawn(Arc::clone(&client));
    let mut app = App::new(options.cluster_id, options.addresses.clone(), worker);

    if let Some(view) = options.dump {
        print!("{}", dump_frame(&mut app, &view));
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

fn run(terminal: &mut ratatui::DefaultTerminal, app: &mut App) -> std::io::Result<()> {
    while !app.quit {
        app.drain();
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
fn dump_frame(app: &mut App, view: &str) -> String {
    match view {
        "transfers" => app.show(View::Transfers),
        "ledgers" => app.show(View::Ledgers),
        "help" => app.toggle_help(),
        _ => {}
    }

    let deadline = std::time::Instant::now() + Duration::from_secs(10);
    while app.loading && std::time::Instant::now() < deadline {
        app.drain();
        std::thread::sleep(Duration::from_millis(50));
    }
    app.drain();

    let mut terminal =
        ratatui::Terminal::new(ratatui::backend::TestBackend::new(130, 20)).expect("test backend");
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
            KeyCode::Char('c') => app.quit = true,
            _ => {}
        }
        return;
    }

    match key.code {
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
        _ => {}
    }
}
