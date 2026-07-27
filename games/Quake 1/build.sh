#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="quake1"

sudo apt-get install -y make build-essential git libsdl2-dev libvorbis-dev libmad0-dev || exit 1

rm -rf quakespasm
git clone https://github.com/sezero/quakespasm.git || error "Could Not Pull Latest Source Code"
cd quakespasm
VERSION=$(awk '$2=="QUAKESPASM_VERSION" && $3~/^[0-9.]+$/ {v=$3} $2=="QUAKESPASM_VER_PATCH" && $3~/^[0-9]+$/ {p=$3} END {print (p != "") ? v "." p : v}' Quake/quakedef.h)
cd Quake

make DO_USERDIRS=1 USE_SDL2=1 -j$(nproc) || error "Compilation failed"

# Compose the DEB package
cd ../../
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/share/quake1
mkdir -p $PACKAGE_NAME/usr/share/quake1/id1
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary file
cp quakespasm/Quake/quakespasm $PACKAGE_NAME/usr/share/quake1/quakespasm

# Data PAK0
curl -L -o /tmp/quake.zip "https://release-assets.githubusercontent.com/github-production-release-asset/729690119/9ede143b-c461-45f2-90e6-5f2859aff799"
unzip -o /tmp/quake.zip -d /tmp/quake
cp /tmp/quake/quake/quakepaks/id1/PAK0.PAK $PACKAGE_NAME/usr/share/quake1/id1/pak0.pak

# Desktop and Icon
sudo tee $PACKAGE_NAME/usr/share/applications/quake1.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Quake 1
Comment=Play the classic 1996 dark fantasy first-person shooter
Exec=/usr/share/quake1/quakespasm -basedir /usr/share/quake1/
Icon=quake1
Terminal=false
Categories=Game;ActionGame;
Keywords=quake;idsoftware;fps;shooter;retro;
EOF
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/quake1.png

rm -rf quakespasm /tmp/quake.zip /tmp/quake

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
