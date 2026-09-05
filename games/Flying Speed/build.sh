#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="flying-speed"
REPO_URL="https://github.com/libredeb/flying-speed.git"
SOURCE_DIR="flying-speed"

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "ERROR: missing icon at $CURRENT_DIR/pkg/icon.png"
    exit 1
fi

# Build dependencies (README: CMake + SDL2 / image / ttf / mixer)
sudo apt-get install -y build-essential cmake pkg-config \
    libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libsdl2-mixer-dev \
    || echo "WARNING: apt-get failed; continuing with already installed packages"

# ── Source ──
rm -rf "$SOURCE_DIR"
git clone --depth=1 "$REPO_URL" "$SOURCE_DIR" || exit 1

VERSION="$(grep -oP 'project\(flying_speed VERSION \K[0-9.]+' "$SOURCE_DIR/CMakeLists.txt")"
if [ -z "$VERSION" ]; then
    echo "ERROR: could not read VERSION from CMakeLists.txt"
    exit 1
fi

# ── Build ──
# PREFIX=/usr so assets resolve via /usr/share/flying-speed/assets (see README).
# Pi Zero 2 W rev 1.0 (Cortex-A53). README uses -j1; this tree is small enough for nproc.
mkdir -p "$SOURCE_DIR/build"
cmake -S "$SOURCE_DIR" -B "$SOURCE_DIR/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=/usr \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_CXX_FLAGS="-O2 -mcpu=cortex-a53 -ftree-vectorize -pipe" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-O1 -Wl,--as-needed" || exit 1

cmake --build "$SOURCE_DIR/build" -j"$(nproc)" || exit 1

# ── Compose the DEB package ──
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"

cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

# Use cmake --install + DESTDIR so Makefile's host desktop/icon cache updates are skipped.
DESTDIR="$CURRENT_DIR/$PACKAGE_NAME" cmake --install "$SOURCE_DIR/build" || exit 1

# Catalog / menu icon (hicolor scalable), matching the rest of the games
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"
install -Dm 644 pkg/icon.png \
    "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/flying-speed.png"

strip --strip-unneeded "$PACKAGE_NAME/usr/bin/flying-speed" 2>/dev/null || true

rm -rf "$SOURCE_DIR"

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
if command -v fakeroot >/dev/null; then
    fakeroot dpkg-deb --build --root-owner-group "$PACKAGE_NAME"
else
    sudo chown -R root:root "$PACKAGE_NAME"
    dpkg-deb --build --root-owner-group "$PACKAGE_NAME"
fi
rm -rf "$PACKAGE_NAME"

echo "Built ${PACKAGE_NAME}.deb"
