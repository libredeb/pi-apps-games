#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="rockbot"
SOURCE_DIR="rockbot"
REPO_URL="https://github.com/protoman/rockbot.git"

# Pi Zero 2 W rev 1.0 (Cortex-A53, 512MB RAM)
PI_CFLAGS="-march=armv8-a+crc -mcpu=cortex-a53 -mtune=cortex-a53 -O3 -pipe"
ORIG_SWAPSIZE=""

cleanup() {
    if [ -n "$ORIG_SWAPSIZE" ] && [ -f /etc/dphys-swapfile ]; then
        echo "Restoring original swap size (${ORIG_SWAPSIZE} MB)..."
        sudo sed -i "s/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=${ORIG_SWAPSIZE}/" /etc/dphys-swapfile
        sudo systemctl restart dphys-swapfile || true
    fi
    rm -rf "$CURRENT_DIR/pkg/__pycache__"
}
trap cleanup EXIT

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "ERROR: missing custom icon at $CURRENT_DIR/pkg/icon.png"
    exit 1
fi

# Expand swap during compile to avoid OOM on 512MB boards
if [ -f /etc/dphys-swapfile ]; then
    ORIG_SWAPSIZE="$(sed -n 's/^CONF_SWAPSIZE=//p' /etc/dphys-swapfile | head -n1)"
    echo "Raising swap to 2048 MB for compilation..."
    sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=2048/' /etc/dphys-swapfile
    sudo systemctl restart dphys-swapfile || true
fi

# Build dependencies (game only, no Qt editor)
sudo apt-get install -y \
    build-essential cmake git pkg-config python3 \
    libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev \
    libsdl2-mixer-dev libsdl2-gfx-dev \
    || exit 1

# ── Source ──
rm -rf "$SOURCE_DIR"
git clone --depth 1 "$REPO_URL" "$SOURCE_DIR" || exit 1

VERSION="$(sed -n 's/^#define VERSION_NUMBER "\(.*\)"/\1/p' "$SOURCE_DIR/file/version.h")"
if [ -z "$VERSION" ]; then
    echo "ERROR: could not read VERSION_NUMBER from file/version.h"
    exit 1
fi

# ── GamerCard gamepad + Hyperpixel 720x720 fill (SDL2) ──
python3 "$CURRENT_DIR/pkg/patch-hyperpixel.py" "$SOURCE_DIR" || exit 1

# ── Build (3 jobs max to stay inside 512MB + swap) ──
CMAKE_BUILD_DIR="$SOURCE_DIR/build/cmake"
rm -rf "$CMAKE_BUILD_DIR"
cmake -S "$SOURCE_DIR" -B "$CMAKE_BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_SDL_VERSION=2 \
    -DCMAKE_C_FLAGS="$PI_CFLAGS" \
    -DCMAKE_CXX_FLAGS="$PI_CFLAGS" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-O1 -Wl,--as-needed" \
    || exit 1

cmake --build "$CMAKE_BUILD_DIR" -j3 || exit 1

BIN=""
for candidate in "$SOURCE_DIR/build/rockbot" "$CMAKE_BUILD_DIR/rockbot"; do
    if [ -x "$candidate" ]; then
        BIN="$candidate"
        break
    fi
done
if [ -z "$BIN" ]; then
    echo "ERROR: rockbot binary not found after cmake --build"
    exit 1
fi
strip --strip-unneeded "$BIN" || true

# ── Compose the DEB package ──
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
GAME_ROOT="$PACKAGE_NAME/usr/share/rockbot"

rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"
mkdir -p "$GAME_ROOT/games"
mkdir -p "$PACKAGE_NAME/usr/bin"
mkdir -p "$PACKAGE_NAME/usr/share/applications"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"
mkdir -p "$PACKAGE_NAME/usr/share/doc/rockbot"

cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

install -Dm 755 "$BIN" "$GAME_ROOT/rockbot"
install -Dm 755 pkg/rockbot "$PACKAGE_NAME/usr/bin/rockbot"

# Game data only (no Qt editor). Keep mp3 so castle intros play with SDL_mixer.
cp -a "$SOURCE_DIR/build/games/RockDroid1" "$GAME_ROOT/games/"
cp -a "$SOURCE_DIR/build/games/RockDroid2" "$GAME_ROOT/games/"
cp -a "$SOURCE_DIR/build/shared" "$GAME_ROOT/"
cp -a "$SOURCE_DIR/build/fonts" "$GAME_ROOT/"
rm -f "$GAME_ROOT/games/RockDroid1/errors.log" "$GAME_ROOT/games/RockDroid2/errors.log"
find "$GAME_ROOT/games" -name '*.sav' -delete
for campaign in RockDroid1 RockDroid2; do
    if [ ! -s "$GAME_ROOT/games/$campaign/maps_v2.dat" ]; then
        echo "ERROR: missing maps_v2.dat for $campaign (needed for stage tiles)"
        exit 1
    fi
done

install -Dm 644 "$SOURCE_DIR/LICENSE" "$PACKAGE_NAME/usr/share/doc/rockbot/copyright"
install -Dm 644 pkg/icon.png "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/rockbot.png"

tee "$PACKAGE_NAME/usr/share/applications/rockbot.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Rockbot
Comment=NES-style Mega Man inspired action platformer
Exec=/usr/bin/rockbot
Icon=rockbot
Terminal=false
Categories=Game;ActionGame;
Keywords=rockbot;megaman;platform;nes;arcade;
StartupNotify=false
EOF

rm -rf "$SOURCE_DIR"
rm -rf "$CURRENT_DIR/pkg/__pycache__"

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
if command -v fakeroot >/dev/null; then
    fakeroot dpkg-deb --build "$PACKAGE_NAME"
else
    sudo chown -R root:root "$PACKAGE_NAME"
    dpkg-deb --build "$PACKAGE_NAME"
fi
rm -rf "$PACKAGE_NAME"

echo "Built ${PACKAGE_NAME}.deb"
