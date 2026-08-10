#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="aircraftwar"

# Build dependencies
sudo apt-get install -y cmake build-essential pkg-config \
    libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev || exit 1

# Build
rm -rf Aircraft-War
git clone -b 16.04 https://github.com/libredeb/Aircraft-War.git || exit 1
cd Aircraft-War/ || exit 1

VERSION=$(grep -oP 'project\(AircraftWar VERSION \K[0-9.]+' sdl2_port/CMakeLists.txt)

mkdir -p sdl2_port/build
cd sdl2_port/build || exit 1

# Compose the DEB package (install prefix must be /usr, not /usr/local)
cd "$CURRENT_DIR" || exit 1
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p "$PACKAGE_NAME/DEBIAN"
mkdir -p "$PACKAGE_NAME/usr/share/applications"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/"

# Debian Control files
cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

INSTALL_PREFIX="$CURRENT_DIR/$PACKAGE_NAME/usr"
cd "$CURRENT_DIR/Aircraft-War/sdl2_port/build" || exit 1
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCMAKE_CXX_FLAGS="-mcpu=cortex-a53" || exit 1
cmake --build . -j"$(nproc)" || exit 1
cmake --install . || exit 1

cd "$CURRENT_DIR" || exit 1

# Desktop and Icon
sudo tee "$PACKAGE_NAME/usr/share/applications/aircraftwar.desktop" <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Aircraft-War
GenericName=Harbour AirCraft War
Comment=Shoot them up aircraft game
Path=/usr/share/aircraftwar/
Exec=/usr/bin/aircraftwar -f
Icon=aircraftwar
Categories=Game;ArcadeGame;
StartupNotify=false
Terminal=false
EOF
cp pkg/icon.png "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/aircraftwar.png"

rm -rf Aircraft-War

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
sudo chown -R root:root "$PACKAGE_NAME"
dpkg-deb --build "$PACKAGE_NAME"
sudo rm -rf "$PACKAGE_NAME"
