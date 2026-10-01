#!/usr/bin/env bash
#
# Build (or update) the evoggy APT repository in $SITE_DIR/apt.
#
# This is incremental: the caller is expected to have seeded $SITE_DIR with the
# currently-published content (from the gh-pages branch) before invoking this
# script. We then drop in the new .deb files for one application, regenerate the
# Packages/Release indices over the *whole* pool, and sign Release.
#
# Only the latest version of each application is kept in the pool (older versions
# remain available on each application's GitHub Releases). Packages are namespaced
# per application under pool/main/<app>/ so re-publishing one app never touches
# another app's files.
#
# Required environment:
#   APP          application name, e.g. "bscli"
#   INCOMING_DIR directory containing the new *.deb files
#   SITE_DIR     output site directory (apt repo is written to $SITE_DIR/apt)
#   GPG_KEY_ID   key id/fingerprint to sign Release with (must already be imported)
#
set -euo pipefail

: "${APP:?APP is required}"
: "${INCOMING_DIR:?INCOMING_DIR is required}"
: "${SITE_DIR:?SITE_DIR is required}"
: "${GPG_KEY_ID:?GPG_KEY_ID is required}"

DIST="stable"
COMPONENT="main"
ARCHES=(amd64 arm64)

# Resolve SITE_DIR to an absolute path: the script cd's into the apt tree to run
# dpkg-scanpackages / apt-ftparchive, so a relative APT_DIR would be re-applied
# from the wrong working directory afterwards.
mkdir -p "${SITE_DIR}"
SITE_DIR="$(cd "${SITE_DIR}" && pwd)"
APT_DIR="${SITE_DIR}/apt"

if ! ls "${INCOMING_DIR}"/*.deb >/dev/null 2>&1; then
    echo "::error::no .deb files found in ${INCOMING_DIR}"
    exit 1
fi

echo "Publishing $(ls "${INCOMING_DIR}"/*.deb | wc -l) .deb file(s) for app '${APP}'"

# Repository skeleton.
mkdir -p "${APT_DIR}/pool/${COMPONENT}/${APP}"
for arch in "${ARCHES[@]}"; do
    mkdir -p "${APT_DIR}/dists/${DIST}/${COMPONENT}/binary-${arch}"
done

# Replace this app's debs (keep only the latest version per app).
rm -f "${APT_DIR}/pool/${COMPONENT}/${APP}"/*.deb
cp "${INCOMING_DIR}"/*.deb "${APT_DIR}/pool/${COMPONENT}/${APP}/"

# Regenerate the Packages index for every architecture over the whole pool.
# Filename: paths are emitted relative to ${APT_DIR}, which is the apt root that
# the `deb` line points at (https://evoggy.github.io/packages/apt).
cd "${APT_DIR}"
for arch in "${ARCHES[@]}"; do
    dpkg-scanpackages --multiversion --arch "${arch}" pool/ \
        > "dists/${DIST}/${COMPONENT}/binary-${arch}/Packages"
    gzip -kf "dists/${DIST}/${COMPONENT}/binary-${arch}/Packages"
done

# Regenerate and sign the Release file.
cd "dists/${DIST}"
cat > Release <<EOF
Origin: evoggy
Label: evoggy
Suite: ${DIST}
Codename: ${DIST}
Architectures: ${ARCHES[*]}
Components: ${COMPONENT}
Description: evoggy package repository
EOF
# apt-ftparchive appends the file hashes and its own Date: field.
apt-ftparchive release . >> Release

gpg --batch --yes --default-key "${GPG_KEY_ID}" -abs -o Release.gpg Release
gpg --batch --yes --default-key "${GPG_KEY_ID}" --clearsign -o InRelease Release
cd - >/dev/null

# Publish the (armored) public key alongside the repo so clients can fetch it.
gpg --armor --export "${GPG_KEY_ID}" > "${APT_DIR}/evoggy.gpg.key"

echo "APT repository written to ${APT_DIR}"
