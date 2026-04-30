#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
# GAME=$(basename "$CURRENT_DIR")
GAME="pacman-sdl"

sudo apt-get install -y libsdl2-dev libsdl2-ttf-dev libsdl2-image-dev libsdl2-mixer-dev automake build-essential || exit 1

rm -rf pacman
# use theofficialgman fork with pacman renamed as pacman_sdl (many code changes) to prevent conflicts with programs that look for 'pacman' as an indicator of an Arch/Manjaro system
git clone https://github.com/theofficialgman/pacman.git || exit 1
cd pacman || error "Could not move to directory"

VERSION=$(sed -n 's/^AC_INIT(\[.*\], \[\(.*\)\])/\1/p' configure.ac)
./autogen.sh || error "Autogen failed"
./configure || error "configure failed"
make -j$(nproc) || error "Could not build source"

# Customizations
wget -qO data/txt/gamecontrollerdb.txt  https://raw.githubusercontent.com/gabomdq/SDL_GameControllerDB/master/gamecontrollerdb.txt
sudo sed -i 's/^Exec=\(.*\)/Exec=env SDL_VIDEODRIVER=wayland \1 -f/' pacman_sdl.desktop
sed -i 's/^Icon=.*/Icon=pacman_sdl/' pacman_sdl.desktop

# Compose the DEB package
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/
mkdir -p $PACKAGE_NAME/usr/local/share/pacman_sdl/fonts
mkdir -p $PACKAGE_NAME/usr/local/share/pacman_sdl/gfx
mkdir -p $PACKAGE_NAME/usr/local/share/pacman_sdl/sounds
mkdir -p $PACKAGE_NAME/usr/local/share/pacman_sdl/txt
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/doc/pacman_sdl

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary
cp pacman/src/pacman_sdl $PACKAGE_NAME/usr/bin/

# Data Files
cp pacman/data/fonts/*.TTF $PACKAGE_NAME/usr/local/share/pacman_sdl/fonts/
cp pacman/data/gfx/*.png $PACKAGE_NAME/usr/local/share/pacman_sdl/gfx/
cp pacman/data/sounds/*.wav $PACKAGE_NAME/usr/local/share/pacman_sdl/sounds/
cp pacman/data/txt/gamecontrollerdb.txt $PACKAGE_NAME/usr/local/share/pacman_sdl/txt/

# Desktop, Docs and Icon
cp pacman/pacman_sdl.desktop $PACKAGE_NAME/usr/share/applications/
cp packman/{README,COPYING,AUTHORS,ChangeLog,INSTALL,NEWS,TODO} $PACKAGE_NAME/usr/share/doc/pacman_sdl/
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/pacman_sdl.png

rm -rf pacman

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
