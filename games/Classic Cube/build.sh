#!/bin/bash
#
# catalog.json — when publishing, the store description must include:
#   Not affiliated with Mojang Studios or Microsoft.
#

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="classic-cube"

# Official ClassiCube CDN. The only texture pack we ship is their own
# redistributable default.zip (saved as texpacks/classicube.zip).
#
# LEGAL: Do not download or package anything from
# resources.download.minecraft.net. ClassiCube's launcher can fetch Mojang
# music (.ogg, including C418) and Classic sound hashes from that CDN, but
# redistributing those assets in a .deb is copyright infringement. This
# recipe never references that host, those hashes, or any Minecraft music.
CC_CDN="https://static.classicube.net"

sudo apt-get install -y build-essential libsdl2-dev libgles2-mesa-dev libgl1-mesa-dev libwayland-dev libopenal-dev ffmpeg zip wget || exit 1

# ── Build from source ──

rm -rf ClassiCube/
git clone https://github.com/ClassiCube/ClassiCube.git --depth=1 && cd ClassiCube || error "Could Not Pull Latest Source Code"
VERSION=$(grep -i "GAME_APP_VER" src/Constants.h | cut -d'"' -f2)

make rpi BUILD_SDL2=1 RELEASE=1

# ── Redistributable assets only ──
#
# Textures: ClassiCube publishes its own pack at $CC_CDN/default.zip.
# It must be stored as texpacks/classicube.zip. Shipping an incomplete
# texpacks/default.zip would block classicube.zip from loading, and a
# "default" pack built from Minecraft jars is not redistributable.
#
# Sounds: pkg/build-freesound-audio.sh builds audio/default.zip from
# redistributable Freesound samples, using the WAV names ClassiCube expects
# (dig_grass1.wav, step_wood1.wav, …):
#   grass/glass/gravel — ClassiCube/doc/sound-credits.md
#   wood/stone         — original CC BY Freesound files used in Classic
#                        (not the processed WAVs from Mojang's CDN)
#   sand/snow/cloth    — CC0 replacements (Classic had no public mapping;
#                        snow was a C418 original)
#
# Music: none. We do not ship C418/Mojang .ogg files. ClassiCube will play
# any .ogg placed in audio/ at runtime; this package leaves that directory
# without music.

mkdir -p texpacks audio

echo "Downloading ClassiCube texture pack (redistributable)..."
wget -q --show-progress "${CC_CDN}/default.zip" -O texpacks/classicube.zip \
    || { echo "ERROR: Failed to download ${CC_CDN}/default.zip"; exit 1; }

if [ ! -f doc/sound-credits.md ]; then
    echo "ERROR: ClassiCube/doc/sound-credits.md missing after clone."
    exit 1
fi

echo "Building audio/default.zip from documented Freesound samples..."
bash "$CURRENT_DIR/pkg/build-freesound-audio.sh" "$(pwd)/audio" || exit 1

# ── Compose the DEB package ──

cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
INSTALL_DIR="/usr/local/games/classic-cube"

mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/texpacks
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/audio
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/plugins
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/maps
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/logs
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/texturecache
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/
mkdir -p $PACKAGE_NAME/usr/share/doc/classic-cube

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary & Data files
cp ClassiCube/ClassiCube $PACKAGE_NAME${INSTALL_DIR}/
cp ClassiCube/license.txt $PACKAGE_NAME${INSTALL_DIR}/ 2>/dev/null || true
cp pkg/options.txt $PACKAGE_NAME${INSTALL_DIR}/
cp pkg/fontscache.txt $PACKAGE_NAME${INSTALL_DIR}/
cp pkg/default.cw $PACKAGE_NAME${INSTALL_DIR}/maps/

# Assets (ClassiCube texture pack + Freesound audio zip only — no Mojang files)
cp ClassiCube/texpacks/classicube.zip $PACKAGE_NAME${INSTALL_DIR}/texpacks/
cp ClassiCube/audio/default.zip $PACKAGE_NAME${INSTALL_DIR}/audio/

# Sound attributions: next to the game binary and under Debian doc
cp ClassiCube/doc/sound-credits.md $PACKAGE_NAME${INSTALL_DIR}/SOUNDS-CREDITS-ClassiCube.md
cp ClassiCube/audio/SOUNDS-CREDITS.txt $PACKAGE_NAME${INSTALL_DIR}/
cp $PACKAGE_NAME${INSTALL_DIR}/SOUNDS-CREDITS-ClassiCube.md $PACKAGE_NAME/usr/share/doc/classic-cube/
cp $PACKAGE_NAME${INSTALL_DIR}/SOUNDS-CREDITS.txt $PACKAGE_NAME/usr/share/doc/classic-cube/

# Wrapper skips the asset-download launcher (map path → RunGame, never Launcher_Run).
install -Dm 755 pkg/classic-cube "$PACKAGE_NAME/usr/bin/classic-cube"
install -Dm 644 pkg/classic-cube.desktop \
    "$PACKAGE_NAME/usr/share/applications/classic-cube.desktop"
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/classic-cube.png

rm -rf ClassiCube/

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
