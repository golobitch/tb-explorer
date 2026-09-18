# tb-tui — TigerBeetle Explorer in the terminal

A read-only terminal browser for [TigerBeetle](https://tigerbeetle.com) clusters, with k9s-style
navigation. Same data as the [macOS app](../ui), on the machine the cluster actually runs on.

> **Status: in progress.** The Rust workspace lands slice by slice; see the root
> [README](../README.md) for what already works.

**Read-only.** `tb-tui` links the six read operations of `tb_client` and nothing else — there is no
create path in the binary to disable. CI fails the build if `create_accounts` or `create_transfers`
appears anywhere under `cli/`.

## Running

```sh
make tb-up      # a local cluster on 127.0.0.1:3000, shared with the macOS app
make cli-run    # cargo run against it
```

## Keys

| Key | What it does |
| --- | ------------ |
| `:` | Command mode — `:accounts`, `:transfers`, `:ledger 840`, `:account 1015`, `:transfer 100539` |
| `ctrl-a` | List every command and alias |
| `/` | Filter the rows on screen |
| `esc` | Back, one view at a time |
| `1` `2` `3` | Accounts, transfers, ledgers |
| `ctrl-r` | Refresh now |
| `?` | Every binding |
| `q` | Quit |

`:` asks the cluster a new question; `/` narrows the answer already on screen. TigerBeetle filters
server-side only on the fields its query filters carry, which is why the two are separate.

## Platforms

macOS (arm64, x86_64) and Linux (arm64, x86_64, glibc). The client uses io_uring on Linux, so a
kernel of 5.6 or newer is required.

## Build

The TigerBeetle client is vendored once for the whole repo in
[`../Vendor/tigerbeetle`](../Vendor/tigerbeetle) and linked statically; `build.rs` picks the archive
matching the target. No network, no Zig toolchain, and the same pinned release the macOS app uses.

```sh
make cli-build   # cargo build
make cli-test    # unit tests, plus integration tests when a cluster is up
```
