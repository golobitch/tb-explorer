# tb-tui — TigerBeetle Explorer in the terminal

A read-only terminal browser for [TigerBeetle](https://tigerbeetle.com) clusters, with k9s-style
navigation. Same data as the [macOS app](../ui), on the machine the cluster actually runs on.

**Read-only.** `tb-tui` links the six read operations of `tb_client` and nothing else — there is no
create path in the binary to disable. CI fails the build if `create_accounts` or `create_transfers`
appears anywhere under `cli/`.

## Install

**Homebrew** (macOS and Linux):

```sh
brew install golobitch/tap/tb-tui
```

**Debian and Ubuntu**, from the apt repository, which keeps `tb-tui` upgrading with everything
else:

```sh
sudo install -d /usr/share/keyrings
curl -fsSL https://golobitch.github.io/tb-explorer/apt/golobitch-archive-keyring.asc \
  | sudo gpg --dearmor -o /usr/share/keyrings/golobitch-archive-keyring.gpg

sudo tee /etc/apt/sources.list.d/tb-explorer.sources >/dev/null <<'EOF'
Types: deb
URIs: https://golobitch.github.io/tb-explorer/apt
Suites: stable
Components: main
Architectures: amd64 arm64
Signed-By: /usr/share/keyrings/golobitch-archive-keyring.gpg
EOF

sudo apt update && sudo apt install tb-tui
```

Debian 12 or newer, Ubuntu 22.04 or newer. The `.deb` from a
[release](https://github.com/golobitch/tb-explorer/releases) installs with `dpkg -i` too.

**A tarball**, for anything else: pick your target from the latest `cli-v*`
[release](https://github.com/golobitch/tb-explorer/releases), check it against `SHA256SUMS`, and
put `tb-tui` on your `PATH`.

## Running

```sh
tb-tui --addresses 127.0.0.1:3000 --cluster 0
```

Against this repo's dev cluster:

```sh
make tb-up      # a local cluster on 127.0.0.1:3000, shared with the macOS app
make cli-run    # cargo run against it
```

## Keys

| Key | What it does |
| --- | ------------ |
| `:` | Command mode — `:accounts`, `:tx 100539`, `:bal 1017`, or a bare id |
| `ctrl-a` | List every command and alias |
| `/` | Filter the rows on screen |
| `enter` | Open the selected row |
| `b` | On an account, swap transfers for balance history |
| `esc` | Back, one view at a time |
| `1` `2` `3` | Accounts, transfers, ledgers |
| `j` `k` `g` `G` | Move; first and last row |
| `o` | Newest first |
| `f` | Amounts as ISO 4217 currency, or exact integers |
| `ctrl-r` / `a` | Refresh now / every 2s |
| `?` | Every binding |
| `q` | Quit |

Auto-refresh pauses while a row is selected, a detail view is open or something is being typed: a
list that moves under the cursor is the one thing that makes k9s unpleasant, and this is a tool for
reading carefully.

`:` asks the cluster a new question; `/` narrows the answer already on screen. TigerBeetle filters
server-side only on the fields its query filters carry, which is why the two are separate.

## What the colours mean

The same vocabulary as the macOS app, so a flag means one thing across both: **pending** yellow,
**posted** green, **voided** and **closed** red, **linked** purple, **history** blue, and a negative
net red. The wordmark top-right doubles as a status light — cyan when idle, yellow while a query is
in flight, red when one failed.

Colours are named ANSI colours, so they inherit whatever scheme your terminal already uses.
`NO_COLOR=1`, or `--no-color`, drops to bold and reverse video only.

## Amounts

Digits are grouped, and `f` switches between the exact integer TigerBeetle stores and the ledger
read as an ISO 4217 currency — ledger 840 shows `1 063 827` or `10 638.27 $`. The exact value is
always one keypress away, and a ledger that is not a currency code is never scaled.

## Platforms

macOS (arm64, x86_64) and Linux (arm64, x86_64, glibc). The client uses io_uring on Linux, so a
kernel of 5.6 or newer is required. The published Linux binaries are built on Debian 12, which puts
the floor at glibc 2.36 — Debian 12, Ubuntu 22.04 and newer.

## Build

The TigerBeetle client is vendored once for the whole repo in
[`../Vendor/tigerbeetle`](../Vendor/tigerbeetle) and linked statically; `build.rs` picks the archive
matching the target. No network, no Zig toolchain, and the same pinned release the macOS app uses.

```sh
make cli-build   # cargo build
make cli-test    # unit tests, plus integration tests when a cluster is up
```

`--dump accounts|transfers|ledgers|help|account:1015|transfer:100539` renders one frame as text
and exits, which is how CI and scripts check real data without a terminal. `--size 80x24` renders
it at a given size, for checking that a narrow terminal still reads well.

## How it is tested

Unit tests pin every struct size and field offset against `tb_client.h` — the same numbers the
Swift client pins — and the integration tests run against the fixture `make tb-up` seeds, asserting
the same answers the Swift suite asserts. Two independent implementations reading the same bytes
and agreeing is the cheapest proof the wire layer is right. Views are rendered into a buffer with
ratatui's `TestBackend`, so layout, breadcrumbs and the help overlay are checked without a tty.
