#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="astromenace"

sudo apt-get install -y g++ cmake make ninja-build libsdl2-dev libogg-dev libvorbis-dev libopenal-dev libalut-dev libfreetype6-dev libglu1-mesa-dev || exit 1

#build
rm -rf astromenace
git clone https://github.com/libredeb/astromenace.git
cd astromenace/
git checkout hyperpixel-version
VERSION=$(grep "GAME_VERSION" src/build_config.h | cut -d '"' -f 2)

mkdir build
cd build || exit 1
cmake .. -G Ninja -DCMAKE_INSTALL_PREFIX=$PWD/../bin -DCMAKE_BUILD_TYPE=Release
cmake --build . --target install

# Compose the DEB package
# We need to go two levels back (outside of astromenace/)
cd ..
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/share/astromenace
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary & Data files
cp astromenace/bin/{astromenace,gamedata.vfs} $PACKAGE_NAME/usr/share/astromenace/

# Desktop and Icon
sudo tee $PACKAGE_NAME/usr/share/applications/astromenace.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=AstroMenace
GenericName=AstroMenace SpaceShooter
Comment=Hardcore 3D space scroll-shooter with spaceship upgrade possibilities
Path=/usr/share/astromenace/
Exec=/usr/share/astromenace/astromenace
Icon=astromenace
Categories=Game;ArcadeGame;
StartupNotify=false
Terminal=false
EOF
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/astromenace.png

rm -rf astromenace

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
