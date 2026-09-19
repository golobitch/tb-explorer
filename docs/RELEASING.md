# Releasing

Three deliverables, three cadences. The website ships on merge; the app and the terminal UI ship on
their own tags, so releasing one never rebuilds the other.

| Deliverable | Version lives in | Tag | Workflow |
| --- | --- | --- | --- |
| macOS app | `ui/project.yml` (`MARKETING_VERSION`) | `ui-v0.1.0` | `release-ui.yml` |
| Terminal UI | `cli/Cargo.toml` (`[workspace.package] version`) | `cli-v0.1.0` | `release-cli.yml` |
| Website | — | — | `pages.yml`, on push to `website/**` |

Tags use a dash, not a slash: `cli/v0.1.0` would collide with a branch named `cli`, and several
tools refuse to parse it.

## Releasing the terminal UI

```sh
# 1. Bump the workspace version and regenerate the lockfile.
$EDITOR cli/Cargo.toml          # [workspace.package] version = "0.1.0"
cd cli && cargo check && cd ..  # rewrites Cargo.lock

# 2. Commit, tag, push.
git commit -am "chore(cli): 0.1.0"
git tag cli-v0.1.0
git push && git push --tags
```

The tag must equal the workspace version; the workflow checks and refuses otherwise. It then
builds four tarballs and two `.deb` packages, publishes them with one `SHA256SUMS`, rebuilds the
apt repository, and points the Homebrew formula at the new release.

The Linux artifacts are built inside a `debian:12` container, which fixes the glibc floor at 2.36
(Debian 12, Ubuntu 22.04 and newer). Building on the runner image instead produces binaries that
need `GLIBC_2.39` and fail to start on anything older.

## Releasing the macOS app

```sh
$EDITOR ui/project.yml          # MARKETING_VERSION, for local builds
git commit -am "chore(ui): 0.1.0"
git tag ui-v0.1.0
git push && git push --tags
```

The tag is the version the app is built with, and the workflow fails if the built
`CFBundleShortVersionString` disagrees. Signing and notarization happen only when the `MACOS_*` and
`APPLE_*` secrets are set; without them the release still publishes, ad-hoc signed.

App releases keep the **Latest** badge. The website's download button follows `/releases/latest`,
so `cli-v*` releases publish with `make_latest: false` deliberately — do not change that without
changing the website too.

## Releasing the website

Merge anything under `website/`. That is the whole procedure.

## One-time setup

Three secrets and one repository, none of which exist until someone makes them. Every workflow
that needs one degrades rather than failing loudly in the wrong place.

**`golobitch/homebrew-tap`** — a public repository named exactly that (the `homebrew-` prefix is
what makes `golobitch/tap` resolve). `bump-tap.yml` writes `Formula/tb-tui.rb` and
`Casks/tb-explorer.rb` into it; nothing else should.

**`TAP_TOKEN`** — a fine-grained PAT with contents:write on the tap and nothing else. Without it
the bump step is skipped and the tap simply goes stale.

**`APT_GPG_PRIVATE_KEY` and `APT_GPG_KEY_ID`** — a signing key made for this purpose, not a
personal key:

```sh
gpg --batch --quick-gen-key "TigerBeetle Explorer apt <you@example.com>" default default never
gpg --list-secret-keys --with-colons | awk -F: '/^fpr/{print $10; exit}'   # APT_GPG_KEY_ID
gpg --armor --export-secret-keys "$KEY_ID"                                 # APT_GPG_PRIVATE_KEY
```

**Back the private key up somewhere outside CI.** Losing it means every existing user's `apt
update` fails until they install a new key by hand. Without the secret, `pages.yml` skips the apt
repository and publishes the site alone — an unsigned repository is never published, because
teaching users to pass `[trusted=yes]` is worse than offering no repository at all.

## Checking a release

```sh
# What users get, verified the way they would verify it.
gh release download cli-v0.1.0 --pattern 'tb-tui-*'
shasum -a 256 -c SHA256SUMS

brew update && brew install golobitch/tap/tb-tui && tb-tui --help
docker run --rm -it debian:12   # then follow cli/README.md's apt instructions
```

## When something goes wrong

A tag is cheap; a wrong release is not. If a release publishes something broken:

1. Delete the release and the tag (`gh release delete cli-v0.1.0 --cleanup-tag`).
2. Fix, bump to the next patch version, tag again. Never move a tag that has been pushed —
   Homebrew and apt have already recorded checksums against it.
3. If the tap or apt repository already updated, re-run `bump-tap.yml` and `pages.yml` for the
   previous good tag to roll them back.
