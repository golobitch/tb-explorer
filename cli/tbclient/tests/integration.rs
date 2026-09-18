//! Runs only when TB_ADDRESS names a cluster, mirroring how the Swift suite is gated.
//!
//! `make tb-up` starts and seeds one on 127.0.0.1:3000.

use std::time::Duration;

use tbclient::{Client, TbError};

fn cluster() -> Option<Client> {
    let address = std::env::var("TB_ADDRESS").ok()?;
    Some(Client::connect(0, &address).expect("connect to the dev cluster"))
}

#[test]
fn connects_and_pings() {
    let Some(client) = cluster() else { return };
    let latency = client.ping().expect("ping");
    assert!(latency < Duration::from_secs(5), "ping took {latency:?}");
}

#[test]
fn an_unreachable_cluster_times_out_rather_than_hanging() {
    let Some(_) = std::env::var("TB_ADDRESS").ok() else {
        return;
    };
    // Port 1 is reserved and nothing listens there.
    let client = Client::connect(0, "127.0.0.1:1").expect("client creation does not connect");
    let error = client
        .submit(
            tbclient::Operation::LookupAccounts,
            0u128.to_le_bytes().to_vec(),
            Duration::from_millis(300),
        )
        .unwrap_err();
    assert!(matches!(error, TbError::Timeout(_)), "got {error:?}");
}
