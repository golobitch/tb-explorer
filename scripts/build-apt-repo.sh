#!/usr/bin/env bash
# Assembles a signed apt repository from the .deb files of the latest cli release.
#
# Nothing is stored: the packages are fetched from the GitHub release each time the site deploys,
# so no binary is ever committed, and the repository is whatever the newest release says it is.
#
#   OUT=website/dist/apt scripts/build-apt-repo.sh
#
# Needs: gh (authenticated), dpkg-dev, apt-utils, gpg with the signing key imported, and
# APT_GPG_KEY_ID naming that key.
set -euo pipefail

OUT="${OUT:-website/dist/apt}"
REPO="${REPO:-golobitch/tb-explorer}"
SUITE="${SUITE:-stable}"
COMPONENT="${COMPONENT:-main}"
ARCHES="${ARCHES:-amd64 arm64}"

log() { echo "[apt] $*"; }

# The newest cli-v* release, not the newest release: the macOS app holds the "latest" badge.
TAG="$(gh release list --repo "$REPO" --limit 50 --json tagName \
  --jq '[.[] | select(.tagName | startswith("cli-v"))] | .[0].tagName // empty')"

if [ -z "$TAG" ]; then
  log "no cli-v* release yet; skipping the repository"
  exit 0
fi

log "building from $TAG"
rm -rf "$OUT"
install -d "$OUT/pool/$COMPONENT/t/tb-tui"
gh release download "$TAG" --repo "$REPO" --pattern '*.deb' --dir "$OUT/pool/$COMPONENT/t/tb-tui"

cd "$OUT"
for arch in $ARCHES; do
  install -d "dists/$SUITE/$COMPONENT/binary-$arch"
  dpkg-scanpackages --arch "$arch" pool/ > "dists/$SUITE/$COMPONENT/binary-$arch/Packages"
  gzip -9fk "dists/$SUITE/$COMPONENT/binary-$arch/Packages"
done

cat > /tmp/apt-ftparchive.conf <<EOF
APT::FTPArchive::Release::Origin "golobitch";
APT::FTPArchive::Release::Label "tb-explorer";
APT::FTPArchive::Release::Suite "$SUITE";
APT::FTPArchive::Release::Codename "$SUITE";
APT::FTPArchive::Release::Architectures "$ARCHES";
APT::FTPArchive::Release::Components "$COMPONENT";
APT::FTPArchive::Release::Description "TigerBeetle Explorer terminal UI";
EOF
apt-ftparchive -c /tmp/apt-ftparchive.conf release "dists/$SUITE" > "dists/$SUITE/Release"

if [ -n "${APT_GPG_KEY_ID:-}" ]; then
  # InRelease is what modern apt fetches; Release.gpg is kept for older clients. Both cost nothing.
  gpg --batch --yes --default-key "$APT_GPG_KEY_ID" \
    --detach-sign --armor -o "dists/$SUITE/Release.gpg" "dists/$SUITE/Release"
  gpg --batch --yes --default-key "$APT_GPG_KEY_ID" \
    --clearsign -o "dists/$SUITE/InRelease" "dists/$SUITE/Release"
  gpg --batch --yes --armor --export "$APT_GPG_KEY_ID" > golobitch-archive-keyring.asc
  log "signed with $APT_GPG_KEY_ID"
else
  # An unsigned repository is worse than none: apt refuses it by default, and a user who works
  # around that has been taught to trust unsigned packages.
  log "APT_GPG_KEY_ID is not set — refusing to publish an unsigned repository"
  exit 1
fi

log "done: $(find . -name '*.deb' | wc -l | tr -d ' ') package(s)"
