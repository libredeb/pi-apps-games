#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="armagetronad"
VERSION="0.2.9.3.0"
SOURCE_DIR="armagetronad-${VERSION}"
SOURCE_URL="https://launchpad.net/~armagetronad-dev/+archive/ubuntu/ppa/+sourcefiles/armagetronad/${VERSION}~ppa1~resolute/armagetronad_${VERSION}~ppa1~resolute.orig.tar.gz"

# Build dependencies. This is an old SDL 1.2 + autotools game.
sudo apt-get install -y build-essential pkg-config wget \
    libsdl1.2-dev libsdl-image1.2-dev libglu1-mesa-dev \
    libxml2-dev libpng-dev libcurl4-openssl-dev zlib1g-dev || exit 1

# Download and extract the source
rm -rf "$SOURCE_DIR" source.tar.gz
wget -q --show-progress -O source.tar.gz "$SOURCE_URL" || exit 1
tar xzf source.tar.gz || exit 1
rm -f source.tar.gz

# GamerCard: this engine predates gamepad support, so the D-pad and a few
# buttons are translated into keyboard events (see the script for details).
python3 "$CURRENT_DIR/pkg/patch-gamepad.py" "$SOURCE_DIR" || exit 1

# Build. --disable-games/--disable-etc/--disable-sysinstall keep everything
# under /usr/bin and /usr/etc instead of decorating paths, touching /etc or
# creating a system user. --disable-uninstall skips generating an uninstaller
# script, which is also dropped since it fails to build from a path with
# spaces (this folder's name has one): we package it as a plain .deb ourselves.
cd "$SOURCE_DIR" || exit 1
mkdir build && cd build || exit 1
../configure --prefix=/usr --disable-sysinstall --disable-games --disable-etc \
    --disable-uninstall --disable-dependency-tracking || exit 1
make -j"$(nproc)" || exit 1
make DESTDIR="$(pwd)/../../package_output" install || exit 1
cd ../..

# Compose the DEB package
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"
cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

# Binary, game data and config. Upstream's own desktop entry, sysinstall
# scripts and uninstaller are dropped: the .deb replaces all of that.
install -Dm 755 package_output/usr/bin/armagetronad "$PACKAGE_NAME/usr/bin/armagetronad"
cp -r package_output/usr/etc "$PACKAGE_NAME/usr/"
mkdir -p "$PACKAGE_NAME/usr/share/armagetronad"
cp -r package_output/usr/share/armagetronad/. "$PACKAGE_NAME/usr/share/armagetronad/"
rm -rf "$PACKAGE_NAME/usr/share/armagetronad/desktop" \
       "$PACKAGE_NAME/usr/share/armagetronad/scripts"

# GamerCard: 720x720 fullscreen + gamepad-friendly key binds, read on every start
install -Dm 644 pkg/autoexec.cfg "$PACKAGE_NAME/usr/etc/armagetronad/autoexec.cfg"

# Desktop entry and icon
install -Dm 644 pkg/armagetronad.desktop "$PACKAGE_NAME/usr/share/applications/armagetronad.desktop"
install -Dm 644 pkg/icon.png "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/armagetronad.png"

rm -rf "$SOURCE_DIR" package_output

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
