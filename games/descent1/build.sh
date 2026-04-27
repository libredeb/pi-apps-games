#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="d1x-rebirth"
VERSION="0.60.0-beta2"

sudo apt-get install -y scons libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-ttf-dev libphysfs-dev libglu1-mesa-dev libgl1-mesa-dev || exit 1

rm -rf dxx-rebirth

git clone https://github.com/dxx-rebirth/dxx-rebirth || exit 1
cd dxx-rebirth
# Fix some wrong declarations
sed -i 's/^static hud_x_scale_float HUD_SCALE_X/static constexpr hud_x_scale_float HUD_SCALE_X/' similar/main/gauges.cpp
sed -i 's/^static hud_y_scale_float HUD_SCALE_Y/static constexpr hud_y_scale_float HUD_SCALE_Y/' similar/main/gauges.cpp
# This targets both overloads of HUD_SCALE_AR
sed -i 's/^static hud_ar_scale_float HUD_SCALE_AR/static constexpr hud_ar_scale_float HUD_SCALE_AR/' similar/main/gauges.cpp
# end fix
scons sdl2=1 sdlmixer=1 d1x=1 -j$(nproc) || error "Failed to compile Descent 1 game engine!"

# Compose the DEB package
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/opt/d1x-rebirth
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/applications

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary and icon
cp dxx-rebirth/build/d1x-rebirth/d1x-rebirth $PACKAGE_NAME/opt/d1x-rebirth/d1x-rebirth
cp pkg/icon.png $PACKAGE_NAME/opt/d1x-rebirth/icon.png

# Shareware Assets
wget https://web.archive.org/web/20221208193117if_/https://www.dxx-rebirth.com/download/dxx/content/descent-pc-shareware.zip
unzip descent-pc-shareware.zip -d $PACKAGE_NAME/opt/d1x-rebirth/
rm descent-pc-shareware.zip

# Hires and Music Packs
wget https://web.archive.org/web/20230702124034if_/https://www.dxx-rebirth.com/download/dxx/res/d1xr-hires.dxa -O $PACKAGE_NAME/opt/d1x-rebirth/d1xr-hires.dxa || error "failed to download hires pack!"
wget https://web.archive.org/web/20221208193318if_/https://www.dxx-rebirth.com/download/dxx/res/d1xr-sc55-music.dxa -O $PACKAGE_NAME/opt/d1x-rebirth/d1xr-sc55-music.dxa  || error "failed to download ogg soundtrack!"

# Configuration
echo -e "ResolutionX=720\nResolutionY=720\nWindowMode=0" > $PACKAGE_NAME/opt/d1x-rebirth/descent.cfg

# Make command asociations
echo '#!/bin/bash
cd /opt/d1x-rebirth
./d1x-rebirth -hogdir /opt/d1x-rebirth "$@"' | tee $PACKAGE_NAME/usr/bin/d1x-rebirth >/dev/null
chmod +x $PACKAGE_NAME/usr/bin/d1x-rebirth

# Make menu launcher
echo "[Desktop Entry]
Name=Descent 1
Comment=DXX-Rebirth source port of Descent
Exec=/usr/bin/d1x-rebirth
Icon=/opt/d1x-rebirth/icon.png
Terminal=false
Type=Application
Categories=Game;ActionGame;
StartupNotify=false" | tee $PACKAGE_NAME/usr/share/applications/d1x-rebirth.desktop >/dev/null

rm -rf dxx-rebirth

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
