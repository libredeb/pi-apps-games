#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="frogatto"
VERSION="1.3.1"

# Upstream (Debian) package + revisions used as source material.
# We don't build Frogatto from source: we reuse the official prebuilt
# binary (contrib) and data files (non-free) and repackage them with our
# own icon.
BIN_DEB_VERSION="1.3.1+dfsg-6+b1"
DATA_DEB_VERSION="1.3.1+dfsg-3"
BIN_POOL_URL="http://deb.debian.org/debian/pool/contrib/f/frogatto"
DATA_POOL_URL="http://deb.debian.org/debian/pool/non-free/f/frogatto-data"
BIN_DEB="frogatto_${BIN_DEB_VERSION}_${TARGET_ARCH}.deb"
DATA_DEB="frogatto-data_${DATA_DEB_VERSION}_all.deb"

WORK_DIR="$CURRENT_DIR/_frogatto-build-work"

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "ERROR: missing icon at $CURRENT_DIR/pkg/icon.png"
    exit 1
fi

command -v dpkg-deb >/dev/null 2>&1 || { echo "ERROR: 'dpkg-deb' is required"; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "ERROR: 'wget' is required"; exit 1; }

# ── Download the official Debian packages (binary + data) ──
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/downloads"

wget -q --show-progress -O "$WORK_DIR/downloads/$BIN_DEB" "$BIN_POOL_URL/$BIN_DEB" || exit 1
wget -q --show-progress -O "$WORK_DIR/downloads/$DATA_DEB" "$DATA_POOL_URL/$DATA_DEB" || exit 1

# ── Extract and reuse their contents ──
mkdir -p "$WORK_DIR/extract/bin" "$WORK_DIR/extract/data"
dpkg-deb -x "$WORK_DIR/downloads/$BIN_DEB" "$WORK_DIR/extract/bin" || exit 1
dpkg-deb -x "$WORK_DIR/downloads/$DATA_DEB" "$WORK_DIR/extract/data" || exit 1

# ── Assemble the DEB package ──
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"

cp -R "$CURRENT_DIR/pkg/DEBIAN/." "$PACKAGE_NAME/DEBIAN/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

# Reuse the official files as-is (binary, data, .desktop, documentation,
# man page...). The binary expects its data under share/games/frogatto,
# which is exactly the path the data package already ships.
mkdir -p "$PACKAGE_NAME/usr"
cp -a "$WORK_DIR/extract/bin/usr/." "$PACKAGE_NAME/usr/"
cp -a "$WORK_DIR/extract/data/usr/." "$PACKAGE_NAME/usr/"

# Remove the icons shipped by the official packages (pixmaps, hicolor and
# share/games): they get replaced by the custom icon.
rm -f "$PACKAGE_NAME/usr/share/pixmaps/frogatto.xpm" \
      "$PACKAGE_NAME/usr/share/pixmaps/frogatto.png" \
      "$PACKAGE_NAME/usr/share/games/frogatto/frogatto.xpm" \
      "$PACKAGE_NAME/usr/share/icons/hicolor/256x256/apps/frogatto.png"

# Custom icon. The original .desktop already uses "Icon=frogatto", so it's
# enough to install it under that same name (no need to edit the .desktop).
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"
install -Dm 644 "$CURRENT_DIR/pkg/icon.png" \
    "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/frogatto.png"

# Fill GamerCard's 720x720 screen by default. Note: plain "--fullscreen"
# is broken here because SDL 1.2's XRandR mode switch to Frogatto's
# default 800x600 leaves no real GL context bound (glewInit then aborts
# with "glew_status != GLEW_OK"), regardless of the GL driver in use.
# Running windowed at the exact panel resolution avoids the mode switch
# entirely and, since there's no window manager, fills the screen anyway.
sed -i "s/^Exec=frogatto$/Exec=frogatto --width 720 --height 720/" \
    "$PACKAGE_NAME/usr/share/applications/frogatto.desktop"

rm -rf "$WORK_DIR"

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
