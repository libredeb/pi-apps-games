#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="marathon2"

version=20250829

sudo apt-get install -y libboost-all-dev libsdl2-dev libglu1-mesa-dev libsdl2-image-dev libsdl2-net-dev libsdl2-ttf-dev libsndfile1-dev libspeexdsp-dev libzzip-dev libavcodec-dev libavformat-dev libopenal-dev libavutil-dev libswscale-dev libswresample-dev libpng-dev libcurl4-openssl-dev libminiupnpc-dev libasio-dev build-essential unzip || exit 1

# Build the source
rm -rf AlephOne-*
wget https://github.com/Aleph-One-Marathon/alephone/releases/download/release-${version}/AlephOne-${version}.tar.bz2 
tar xjvf AlephOne-${version}.tar.bz2 || error "Unable to decompress source code"
rm -f AlephOne-*.tar.bz2
cd AlephOne-${version}
VERSION=$(grep 'define A1_DISPLAY_VERSION' Source_Files/Misc/alephversion.h | cut -d'"' -f2)
./configure --prefix=/usr
make -j$(nproc)
make DESTDIR=$(pwd)/../pkg_output install

# Compose the DEB package
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/alephone/marathon2
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Move Engine binaries and shared data (MML, Plugins)
cp -r pkg_output/usr/bin/* $PACKAGE_NAME/usr/bin/
cp -r pkg_output/usr/share/AlephOne $PACKAGE_NAME/usr/share/
cp -r pkg_output/usr/share/icons $PACKAGE_NAME/usr/share/
cp -r pkg_output/usr/share/mime $PACKAGE_NAME/usr/share/
cp -r pkg_output/usr/share/man $PACKAGE_NAME/usr/share/

# Move Marathon 2 Data Files (The .zip content)
wget https://github.com/Aleph-One-Marathon/alephone/releases/download/release-${version}/Marathon2-${version}-Data.zip || exit 1
unzip Marathon2-${version}-Data.zip
cp -r "Marathon 2"/* $PACKAGE_NAME/usr/share/alephone/marathon2/
rm -rf Marathon*-Data.zip "Marathon 2"/

# Make menu launcher and copy icon
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/marathon2.png
echo "[Desktop Entry]
Version=1.0
Name=Marathon 2
Comment=Sci-fi first-person shooter
Exec=/usr/bin/alephone /usr/share/alephone/marathon2/ %u
Icon=marathon2
Terminal=false
Type=Application
Categories=Game;ActionGame;" | tee $PACKAGE_NAME/usr/share/applications/marathon2.desktop >/dev/null

rm -rf AlephOne-${version}
rm -rf pkg_output

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
