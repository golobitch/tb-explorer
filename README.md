# TigerBeetle Explorer

Read-only browsers for [TigerBeetle](https://tigerbeetle.com) clusters: ledgers, accounts,
transfers, balance history, and pending → post/void chains.

**Website:** [golobitch.github.io/tb-explorer](https://golobitch.github.io/tb-explorer/)

**Read-only, and checked.** Nothing here issues `create_accounts` or `create_transfers` — CI fails
the build if either string appears in a front end. The only code that writes to a cluster is
`ui/Tools/tb-seed`, which exists to seed a local dev cluster.

| Folder | What it is |
| ------ | ---------- |
| [`ui/`](ui) | The native macOS app (SwiftUI). Point it at a cluster and browse. |
| [`cli/`](cli) | A terminal UI (Rust, ratatui) with k9s-style navigation, for the machine the cluster runs on. macOS and Linux, and [themeable](cli/README.md#themes) — Nord, Dracula, One Dark and seven more, or write your own. |
| [`website/`](website) | The landing page (Astro), deployed to GitHub Pages. |

Both front ends talk to TigerBeetle through the official C client (`tb_client`), vendored once in
[`Vendor/tigerbeetle/`](Vendor/tigerbeetle) and shared. They are pinned to the same release, and CI
checks the pin.

![TigerBeetle Explorer showing an account's balances and transfers](docs/images/app-accounts-view.png)

## Install

```sh
brew install --cask golobitch/tap/tb-explorer   # the macOS app
brew install golobitch/tap/tb-tui               # the terminal UI, macOS and Linux
```

On Debian and Ubuntu the terminal UI comes from an apt repository, so it upgrades with everything
else — see [`cli/README.md`](cli/README.md#install) for the keyring and `.sources` file. Every
release also publishes plain downloads and one `SHA256SUMS`: the notarized app zip under a `ui-v*`
tag, four tarballs and two `.deb`s under a `cli-v*` tag.

## Version compatibility

Each deliverable is versioned and tagged on its own, so releasing one never moves the other. The
TigerBeetle client is compiled into both front ends and must be compatible with the server; a
mismatch surfaces as a refusal to connect rather than as wrong data.

| Deliverable | Version lives in | Tag | tb_client | TigerBeetle server |
| ----------- | ---------------- | --- | --------- | ------------------ |
| macOS app | `ui/project.yml` | `ui-v0.0.x` | 0.17.9 | 0.17.9 |
| Terminal UI | `cli/Cargo.toml` | `cli-v0.0.x` | 0.17.9 | 0.17.9 |
| Website | — | deploys on merge | — | — |

Both front ends are pinned to the same vendored client, and each has a test that fails when its
version constant and [`Vendor/tigerbeetle/VERSION`](Vendor/tigerbeetle) disagree. How to cut a
release is in [`docs/RELEASING.md`](docs/RELEASING.md).

## Getting started

```sh
make tb-up           # download, format, start and seed a local cluster on 127.0.0.1:3000
make open            # generate the Xcode project and open the macOS app
make cli-run         # run the terminal UI against the same cluster
make test            # the macOS app's suites
make cli-test        # the terminal UI's suites
```

Both front ends share one `Makefile` at the root, so a dev cluster started once serves whichever
you are working on. `make tb-stop` stops it; `make tb-reset` throws the data away.

## Layout

```
Makefile              one entry point for both front ends and the shared dev cluster
Vendor/tigerbeetle/   tb_client.h, module map, the static libraries, VERSION
scripts/              dev-cluster.sh, render-icon.swift, build-apt-repo.sh
packaging/homebrew/   the formula and cask templates the tap is rendered from
docs/RELEASING.md     what to bump, what to tag, and what happens next
docs/images/          screenshots used by the READMEs
ui/                   macOS app — see ui/README.md
cli/                  terminal UI — see cli/README.md
website/              landing page — see website/README.md
```

Each folder has its own README covering how to build, test and release it.

## Licence

MIT — see [LICENSE](LICENSE). `website/LICENCE.md` covers the Astro theme the landing page is built
from, and belongs to its author.

## Upgrading TigerBeetle

`make vendor TB_VERSION=x.y.z` refreshes the client for **both** front ends from the
`tigerbeetle-go` module of that release. Then update the version constant each front end carries —
`TBClient.clientVersion` and `tbclient::CLIENT_VERSION` — and run `make test` and `make cli-test`,
which fail when a constant and the vendored `VERSION` disagree.
