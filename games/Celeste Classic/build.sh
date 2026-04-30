#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="ccleste"

sudo apt-get install -y build-essential libsdl2-mixer-dev libsdl2-dev libsdl2-image-dev libsndio-dev || exit 1

rm -rf ccleste
git clone https://github.com/lemon32767/ccleste.git --depth=1 && cd ccleste || error "Could Not Pull Latest Source Code"
VERSION=$(RAW=$(git describe --tags --abbrev=0 2>/dev/null) && echo "${RAW#v}")

rm -rf gamecontrollerdb.txt
make -j$(nproc) || error "Compilation failed"
wget https://raw.githubusercontent.com/gabomdq/SDL_GameControllerDB/master/gamecontrollerdb.txt

# Compose the DEB package
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/share/ccleste
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary & Data files
cp ccleste/{ccleste,gamecontrollerdb.txt,icon.png,screenshot.png} $PACKAGE_NAME/usr/share/ccleste/
cp -r ccleste/data $PACKAGE_NAME/usr/share/ccleste/
echo "True" > $PACKAGE_NAME/usr/share/ccleste/ccleste-start-fullscreen.txt

# Desktop and Icon
sudo tee $PACKAGE_NAME/usr/share/applications/ccleste.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Celeste Classic
Comment=Hardcore mountain-climbing platformer
Exec=/usr/share/ccleste/ccleste
Path=/usr/share/ccleste
Icon=ccleste
Terminal=false
Categories=Game;
EOF
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/ccleste.png

rm -rf ccleste

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
