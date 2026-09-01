#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="vaixterm"
REPO_URL="https://github.com/libredeb/vaixterm.git"
SOURCE_DIR="vaixterm"

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "ERROR: missing icon at $CURRENT_DIR/pkg/icon.png"
    exit 1
fi

# Build dependencies (README / Makefile). libvterm is vendored; no libvterm-dev.
sudo apt-get install -y build-essential pkg-config wget \
    libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev || exit 1

# ── Source ──
rm -rf "$SOURCE_DIR"
git clone --depth=1 "$REPO_URL" "$SOURCE_DIR" || exit 1

VERSION="$(sed -n 's/^#define VERSION "\(.*\)"/\1/p' "$SOURCE_DIR/include/config.h")"
if [ -z "$VERSION" ]; then
    echo "ERROR: could not read VERSION from include/config.h"
    exit 1
fi

# ── Build ──
make -C "$SOURCE_DIR" -j"$(nproc)" || exit 1

# ── Compose the DEB package ──
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"

cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

make -C "$SOURCE_DIR" PREFIX=/usr DESTDIR="$CURRENT_DIR/$PACKAGE_NAME" install || exit 1

# Wrapper owns GamerCard mapping + handheld flags; real binary under /usr/lib
mkdir -p "$PACKAGE_NAME/usr/lib/vaixterm"
mv "$PACKAGE_NAME/usr/bin/vaixterm" "$PACKAGE_NAME/usr/lib/vaixterm/vaixterm"
install -Dm 755 pkg/vaixterm "$PACKAGE_NAME/usr/bin/vaixterm"

# Desktop + hicolor icon (Icon=vaixterm; Path so relative res/ files resolve)
install -Dm 644 pkg/vaixterm.desktop \
    "$PACKAGE_NAME/usr/share/applications/vaixterm.desktop"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"
install -Dm 644 pkg/icon.png \
    "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/vaixterm.png"

if [ -f "$SOURCE_DIR/LICENSE" ]; then
    install -Dm 644 "$SOURCE_DIR/LICENSE" \
        "$PACKAGE_NAME/usr/share/doc/vaixterm/copyright"
fi

rm -rf "$SOURCE_DIR"

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
if command -v fakeroot >/dev/null; then
    fakeroot dpkg-deb --build --root-owner-group "$PACKAGE_NAME"
else
    dpkg-deb --build --root-owner-group "$PACKAGE_NAME"
fi
rm -rf "$PACKAGE_NAME"

echo "Built ${PACKAGE_NAME}.deb"
