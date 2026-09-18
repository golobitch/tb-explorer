use std::time::Duration;

use tbclient::{CLIENT_VERSION, Client};

/// Placeholder entry point: connects, reports, exits. The interface lands in the next slices.
fn main() {
    let addresses = std::env::args()
        .skip_while(|a| a != "--addresses")
        .nth(1)
        .unwrap_or_else(|| "127.0.0.1:3000".to_string());

    match Client::connect(0, &addresses) {
        Ok(client) => {
            println!("tb-tui · client {CLIENT_VERSION} · connected to {addresses}");
            drop(client);
        }
        Err(error) => {
            eprintln!("tb-tui: {error}");
            std::process::exit(1);
        }
    }
    let _ = Duration::from_secs(0);
}
