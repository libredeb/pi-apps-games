#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="d2x-rebirth"
VERSION="0.60.0-beta2"

sudo apt-get install -y scons libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev libphysfs-dev libglu1-mesa-dev libgl1-mesa-dev || exit 1

rm -rf dxx-rebirth

git clone https://github.com/dxx-rebirth/dxx-rebirth || exit 1
cd dxx-rebirth
# Fix some wrong declarations
sed -i 's/^static hud_x_scale_float HUD_SCALE_X/static constexpr hud_x_scale_float HUD_SCALE_X/' similar/main/gauges.cpp
sed -i 's/^static hud_y_scale_float HUD_SCALE_Y/static constexpr hud_y_scale_float HUD_SCALE_Y/' similar/main/gauges.cpp
sed -i 's/^static hud_ar_scale_float HUD_SCALE_AR/static constexpr hud_ar_scale_float HUD_SCALE_AR/' similar/main/gauges.cpp
# end fix
scons sdl2=1 sdlmixer=1 d2x=1 -j$(nproc) || error "Failed to compile Descent 2 game engine!"

# Compose the DEB package
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/opt/d2x-rebirth
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/applications

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary and icon
cp dxx-rebirth/build/d2x-rebirth/d2x-rebirth $PACKAGE_NAME/opt/d2x-rebirth/
cp pkg/icon.png $PACKAGE_NAME/opt/d2x-rebirth/icon.png

# Download Demo Data
wget https://web.archive.org/web/20221208193117if_/https://www.dxx-rebirth.com/download/dxx/content/descent2-pc-demo.zip
unzip descent2-pc-demo.zip -d $PACKAGE_NAME/opt/d2x-rebirth/
rm descent2-pc-demo.zip

# Rename to lower case (important for Linux case-sensitivity)
cd $PACKAGE_NAME/opt/d2x-rebirth
for i in $( ls | grep [A-Z] ); do mv -f $i `echo $i | tr 'A-Z' 'a-z'`; done
cd -

# Music Pack
wget https://web.archive.org/web/20221208193318if_/https://www.dxx-rebirth.com/download/dxx/res/d2xr-sc55-music.dxa -O $PACKAGE_NAME/opt/d2x-rebirth/d2xr-sc55-music.dxa

# Configuration
echo -e "ResolutionX=720\nResolutionY=720\nWindowMode=0" > $PACKAGE_NAME/opt/d2x-rebirth/descent.cfg

# Make command asociations
echo '#!/bin/bash
cd /opt/d2x-rebirth
./d2x-rebirth -hogdir /opt/d2x-rebirth "$@"' | tee $PACKAGE_NAME/usr/bin/d2x-rebirth >/dev/null
chmod +x $PACKAGE_NAME/usr/bin/d2x-rebirth

# Make menu launcher
echo "[Desktop Entry]
Name=Descent 2
Comment=DXX-Rebirth source port of Descent 2
Exec=/usr/bin/d2x-rebirth
Icon=/opt/d2x-rebirth/icon.png
Terminal=false
Type=Application
Categories=Game;ActionGame;
StartupNotify=false" | tee $PACKAGE_NAME/usr/share/applications/d2x-rebirth.desktop >/dev/null

rm -rf dxx-rebirth

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
