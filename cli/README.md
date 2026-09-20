# tb-tui — TigerBeetle Explorer in the terminal

A read-only terminal browser for [TigerBeetle](https://tigerbeetle.com) clusters, with k9s-style
navigation. Same data as the [macOS app](../ui), on the machine the cluster actually runs on.

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

By default those are named ANSI colours, so they inherit whatever scheme your terminal already
uses. `NO_COLOR=1`, or `--no-color`, drops to bold and reverse video only — and wins over any
theme.

## Themes

```sh
tb-tui --list-themes            # ansi, mono, andromeda, catppuccin-mocha, dracula,
                                # gruvbox-dark, nord, one-dark, solarized-dark, tokyo-night
tb-tui --theme nord             # just this run
```

Or press `:` and type `theme` for a list you can arrow through. The screen repaints as you move,
so you choose by looking; `enter` keeps it and `esc` puts back the one you arrived with. Keeping a
theme writes `theme = nord` into `~/.config/tb-tui/config` — **the only file tb-tui ever writes**,
and it never writes to a cluster.

Everything else is a preset: `ansi` is what ships, and the other eight name hex colours, which a
terminal without truecolor cannot show. Muted text in each is lifted to at least 3:1 against that
theme's own background, because a hint you cannot read is not a hint.

### Writing your own

Start from one, and edit:

```sh
mkdir -p ~/.config/tb-tui/themes
tb-tui --dump-theme nord > ~/.config/tb-tui/themes/mine.theme
tb-tui --theme mine
```

A file in `~/.config/tb-tui/themes/` shadows the preset of the same name, so you can adjust `nord`
without renaming it. A theme only has to name the roles it changes — everything else keeps its
default, so this is a complete theme:

```
# ~/.config/tb-tui/themes/mine.theme
border.focus = #88c0d0
flag.pending = #ebcb8b bold
```

One role per line, `role = fg [on bg] [modifiers]`. A colour is a name (`cyan`, `bright_black`), a
hex triplet (`#88c0d0`), a palette index (`0`–`255`), or `default` for whatever the terminal
already uses. Modifiers are `bold`, `dim`, `italic`, `underline`, `reverse` and `crossed`. A line
starting with `#` is a comment, and elsewhere `#` only begins one when a space follows — so
`#88c0d0` stays a colour. Mistakes name their own line:

```
mine.theme:7: unknown role "boarder" — did you mean "border"?
```

The presets set a background on `text`; delete the `on …` to keep your terminal's own, transparency
included.

### The roles

| Group | Roles |
| --- | --- |
| Base | `text` — painted under everything, so untyped text belongs to the theme too |
| Chrome | `border`, `border.focus`, `title`, `title.scope`, `title.count`, `label`, `value`, `key`, `hint`, `logo`, `badge` |
| Table | `table.header`, `table.cursor`, `table.stripe`, `table.id`, `table.number` |
| State | `good`, `warn`, `bad`, `busy` |
| Flags | `flag.pending`, `flag.posted`, `flag.voided`, `flag.closed`, `flag.linked`, `flag.history`, `flag.other` |
| Verdict | `status.posted`, `status.voided`, `status.expired`, `status.pending`, `status.unknown` |
| Amounts | `net.negative`, `net.positive` |

`tb-tui --dump-theme` prints the lot with their current values. Which theme you get, highest first:
`--theme`, `TB_TUI_THEME`, `~/.config/tb-tui/config`, then `ansi`. A theme named on the command
line that will not load is an error; a broken one in the config is reported in the footer and
ignored, because a preference should not stand between you and a cluster.

## Amounts

Digits are grouped, and `f` switches between the exact integer TigerBeetle stores and the ledger
read as an ISO 4217 currency — ledger 840 shows `1 063 827` or `10 638.27 $`. The exact value is
always one keypress away, and a ledger that is not a currency code is never scaled.

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

`--dump accounts|transfers|ledgers|help|account:1015|transfer:100539` renders one frame as text
and exits, which is how CI and scripts check real data without a terminal. `--size 80x24` renders
it at a given size, for checking that a narrow terminal still reads well.

## How it is tested

Unit tests pin every struct size and field offset against `tb_client.h` — the same numbers the
Swift client pins — and the integration tests run against the fixture `make tb-up` seeds, asserting
the same answers the Swift suite asserts. Two independent implementations reading the same bytes
and agreeing is the cheapest proof the wire layer is right. Views are rendered into a buffer with
ratatui's `TestBackend`, so layout, breadcrumbs and the help overlay are checked without a tty.
