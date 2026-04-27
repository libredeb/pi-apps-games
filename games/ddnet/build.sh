#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
# GAME=$(basename "$CURRENT_DIR")
GAME="ddnet"
VERSION=19.8.2


#Dependencies
sudo apt-get install -y build-essential cargo cmake git libcurl4-openssl-dev libssl-dev libfreetype6-dev libgles2-mesa-dev libglew-dev libnotify-dev libogg-dev libopus-dev libopusfile-dev libpnglite-dev libsdl2-dev libsqlite3-dev libwavpack-dev python3 google-mock libx264-dev libavfilter-dev libavdevice-dev libavformat-dev libavcodec-dev libavutil-dev rustc glslang-tools libvulkan-dev || exit 1

#Clone the Repository
git clone https://github.com/ddnet/ddnet --recursive -b $VERSION --depth=1 || exit 1

#Build
cd ddnet || exit 1
mkdir build
cd build || exit 1
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DVULKAN=ON || error 'Failed at cmake!'
make -j$(nproc) || error 'Failed at make!'
make DESTDIR=$(pwd)/../package_output install

# Compose the DEB package
# We need 2 cd to exit from 'build' directory and exit from 'ddnet' too
cd ..
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/ddnet
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Move files from the temporary output to the DEB structure
cp -r ddnet/package_output/usr/bin/* $PACKAGE_NAME/usr/bin/
cp -r ddnet/package_output/usr/share/ddnet/* $PACKAGE_NAME/usr/share/ddnet/
cp -r ddnet/package_output/usr/share/applications/* $PACKAGE_NAME/usr/share/applications/
cp -r ddnet/package_output/usr/share/icons/* $PACKAGE_NAME/usr/share/icons/

# Custom Icon
cp pkg/icon.png $PACKAGE_NAME/usr/share/ddnet/custom_icon.png
sed -i 's/^Icon=.*/Icon=\/usr\/share\/ddnet\/custom_icon.png/' $PACKAGE_NAME/usr/share/applications/ddnet.desktop

rm -rf ddnet

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
