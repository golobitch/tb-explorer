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

// The fixture below is the one `ui/Tools/tb-seed` writes and the Swift suite asserts against:
// accounts 1001–1020, transfers 100001 and up, ledgers 700 and 840. Two independent clients
// reading the same bytes and agreeing is the cheapest proof the wire layer is right.

#[test]
fn looks_up_seeded_accounts() {
    let Some(client) = cluster() else { return };
    let accounts = client.lookup_accounts(&[1001, 1015]).expect("lookup");
    assert_eq!(accounts.len(), 2);
    assert_eq!(accounts[0].id, 1001);
    assert!(accounts.iter().all(|a| a.ledger == 700 || a.ledger == 840));
    assert!(accounts.iter().all(|a| a.timestamp > 0));
}

#[test]
fn an_unknown_id_is_absent_rather_than_an_error() {
    let Some(client) = cluster() else { return };
    assert!(
        client
            .lookup_accounts(&[999_999_999])
            .expect("lookup")
            .is_empty()
    );
    assert_eq!(
        client.lookup_id(999_999_999).expect("lookup"),
        tbclient::Found::Nothing
    );
}

#[test]
fn tells_an_account_from_a_transfer() {
    let Some(client) = cluster() else { return };
    assert!(matches!(
        client.lookup_id(1001).expect("lookup"),
        tbclient::Found::Account(_)
    ));
    assert!(matches!(
        client.lookup_id(100_001).expect("lookup"),
        tbclient::Found::Transfer(_)
    ));
}

#[test]
fn query_accounts_pages_by_timestamp_cursor() {
    use tbclient::{QueryFilter, next_cursor};
    let Some(client) = cluster() else { return };

    let all = client
        .query_accounts(&QueryFilter {
            ledger: 840,
            limit: 100,
            ..Default::default()
        })
        .expect("query");
    assert!(
        all.len() >= 2,
        "the seed puts several accounts in ledger 840"
    );

    let first = client
        .query_accounts(&QueryFilter {
            ledger: 840,
            limit: 1,
            ..Default::default()
        })
        .expect("query");
    assert_eq!(first.len(), 1);

    let (min, max) = next_cursor(first[0].timestamp, false);
    let second = client
        .query_accounts(&QueryFilter {
            ledger: 840,
            limit: 1,
            timestamp_min: min,
            timestamp_max: max,
            ..Default::default()
        })
        .expect("query");
    assert_eq!(second.len(), 1);
    assert_eq!(
        second[0].id, all[1].id,
        "the cursor must not skip or repeat a row"
    );
}

#[test]
fn account_transfers_respect_the_side_filter() {
    use tbclient::AccountFilter;
    let Some(client) = cluster() else { return };
    let both = client
        .account_transfers(&AccountFilter {
            account_id: 1001,
            limit: 200,
            ..Default::default()
        })
        .expect("transfers");
    let debits = client
        .account_transfers(&AccountFilter {
            account_id: 1001,
            limit: 200,
            credits: false,
            ..Default::default()
        })
        .expect("transfers");

    assert!(!both.is_empty(), "account 1001 has transfers in the seed");
    assert!(debits.len() <= both.len());
    assert!(debits.iter().all(|t| t.debit_account_id == 1001));
}

#[test]
fn balances_come_back_only_for_history_accounts() {
    use tbclient::{AccountFilter, models::account_flags};
    let Some(client) = cluster() else { return };

    let accounts = client.lookup_accounts(&[1001, 1007]).expect("lookup");
    for account in accounts {
        let balances = client
            .account_balances(&AccountFilter {
                account_id: account.id,
                limit: 10,
                ..Default::default()
            })
            .expect("balances");
        if account.flags & account_flags::HISTORY != 0 {
            assert!(!balances.is_empty(), "account {} has history", account.id);
            assert!(balances.iter().all(|b| b.timestamp > 0));
        } else {
            assert!(
                balances.is_empty(),
                "account {} has no history flag",
                account.id
            );
        }
    }
}

#[test]
fn a_reversed_query_returns_newest_first() {
    use tbclient::QueryFilter;
    let Some(client) = cluster() else { return };
    let newest = client
        .query_transfers(&QueryFilter {
            limit: 5,
            reversed: true,
            ..Default::default()
        })
        .expect("query");
    let oldest = client
        .query_transfers(&QueryFilter {
            limit: 5,
            ..Default::default()
        })
        .expect("query");

    assert_eq!(newest.len(), 5);
    assert!(newest[0].timestamp > oldest[0].timestamp);
    assert!(newest.windows(2).all(|w| w[0].timestamp > w[1].timestamp));
}

#[test]
fn resolves_pending_transfers_the_way_the_swift_client_does() {
    use tbclient::{DEFAULT_LOOKBACK, PendingStatus, models::transfer_flags};
    let Some(client) = cluster() else { return };

    // The seed writes posted, voided, expired and never-resolved pendings; find one of each shape
    // by walking the transfers it created.
    let transfers = client
        .query_transfers(&tbclient::QueryFilter {
            limit: 600,
            ..Default::default()
        })
        .expect("query");
    let pendings: Vec<_> = transfers
        .iter()
        .filter(|t| t.flags & transfer_flags::PENDING != 0)
        .collect();
    assert!(!pendings.is_empty(), "the seed creates pending transfers");

    // The seed writes its pendings in batches — all the posted ones, then the voided ones — so a
    // sample has to be spread across the set rather than taken from the front.
    let step = (pendings.len() / 12).max(1);
    let mut seen = Vec::new();
    for pending in pendings.iter().step_by(step) {
        let chain = client.chain(pending.id, DEFAULT_LOOKBACK).expect("chain");
        let resolution = chain
            .resolution
            .expect("a pending transfer has a resolution");
        seen.push(resolution.status);

        match resolution.status {
            PendingStatus::Posted => assert!(
                resolution
                    .resolutions
                    .iter()
                    .any(|t| t.flags & transfer_flags::POST_PENDING_TRANSFER != 0)
            ),
            PendingStatus::Voided => assert!(
                resolution
                    .resolutions
                    .iter()
                    .any(|t| t.flags & transfer_flags::VOID_PENDING_TRANSFER != 0)
            ),
            _ => {}
        }
    }
    assert!(
        seen.contains(&PendingStatus::Posted) && seen.contains(&PendingStatus::Voided),
        "the seed has both posted and voided pendings; saw {seen:?}"
    );
}

#[test]
fn a_post_points_back_at_its_pending() {
    use tbclient::{DEFAULT_LOOKBACK, models::transfer_flags};
    let Some(client) = cluster() else { return };

    let transfers = client
        .query_transfers(&tbclient::QueryFilter {
            limit: 600,
            ..Default::default()
        })
        .expect("query");
    let post = transfers
        .iter()
        .find(|t| t.flags & transfer_flags::POST_PENDING_TRANSFER != 0)
        .expect("the seed posts some pendings");

    let chain = client.chain(post.id, DEFAULT_LOOKBACK).expect("chain");
    let pending = chain.pending.expect("a post names the pending it resolves");
    assert_eq!(pending.id, post.pending_id);
    assert_ne!(pending.flags & transfer_flags::PENDING, 0);
}

#[test]
fn linked_groups_come_back_whole() {
    use tbclient::{DEFAULT_LOOKBACK, models::transfer_flags};
    let Some(client) = cluster() else { return };

    let transfers = client
        .query_transfers(&tbclient::QueryFilter {
            limit: 600,
            ..Default::default()
        })
        .expect("query");
    let linked = transfers
        .iter()
        .find(|t| t.flags & transfer_flags::LINKED != 0)
        .expect("the seed writes linked groups");

    let chain = client.chain(linked.id, DEFAULT_LOOKBACK).expect("chain");
    assert!(chain.linked.len() > 1, "a linked transfer has company");
    assert!(
        chain
            .linked
            .windows(2)
            .all(|w| w[1].timestamp == w[0].timestamp + 1),
        "a linked group is contiguous in time"
    );
    assert!(chain.linked.iter().any(|t| t.id == linked.id));
}

/// The Swift client has asserted this since the start (`FormatTests.vendoredVersionMatches`); the
/// Rust one did not, so a `make vendor` bump could leave this crate claiming the old release while
/// linking the new archive. Runs with or without a cluster.
#[test]
fn the_client_version_matches_the_vendored_archive() {
    // cli/tbclient/tests/ → the repo root, where Vendor is shared with the macOS app.
    let vendored =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Vendor/tigerbeetle/VERSION");
    let expected = std::fs::read_to_string(&vendored)
        .unwrap_or_else(|error| panic!("reading {}: {error}", vendored.display()));
    assert_eq!(expected.trim(), tbclient::CLIENT_VERSION);
}
