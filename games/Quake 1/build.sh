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
curl -L -o /tmp/quake.zip "https://github.com/libredeb/pi-apps-games/releases/download/v12-bookworm.arm64/quake.zip"
unzip -o /tmp/quake.zip -d /tmp/quake
cp /tmp/quake/quake/quakepaks/id1/PAK0.PAK $PACKAGE_NAME/usr/share/quake1/id1/pak0.pak

# Desktop and Icon
sudo tee $PACKAGE_NAME/usr/share/applications/quake1.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Quake 1
Comment=Play the classic 1996 dark fantasy first-person shooter
Exec=env SDL_GAMECONTROLLERCONFIG="03000000412300003680000001010000,Arduino Leonardo,a:b0,b:b1,x:b3,y:b4,back:b10,start:b11,leftshoulder:b7,rightshoulder:b6,rightx:a0,lefty:a1,platform:Linux," /usr/share/quake1/quakespasm -basedir /usr/share/quake1/ +cl_yawspeed 50 +joy_yawspeed 50 +cl_pitchspeed 60
Icon=quake1
Terminal=false
Categories=Game;ActionGame;
Keywords=quake;idsoftware;fps;shooter;retro;
EOF
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/quake1.png

# HyperPixel config
cp pkg/hyperpixel.cfg $PACKAGE_NAME/usr/share/quake1/hyperpixel.cfg

rm -rf quakespasm /tmp/quake.zip /tmp/quake

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
