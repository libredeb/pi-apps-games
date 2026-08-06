#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
MOJANG_CDN="https://resources.download.minecraft.net"
CC_CDN="http://static.classicube.net"
GAME="classic-cube"

download_mojang() {
    local hash="$1" dest="$2"
    local prefix="${hash:0:2}"
    wget -q --show-progress -O "$dest" "${MOJANG_CDN}/${prefix}/${hash}"
}

sudo apt-get install -y build-essential libsdl2-dev libgles2-mesa-dev libgl1-mesa-dev libwayland-dev libopenal-dev || exit 1

# ── Build from source ──

rm -rf ClassiCube/
git clone https://github.com/ClassiCube/ClassiCube.git --depth=1 && cd ClassiCube || error "Could Not Pull Latest Source Code"
VERSION=$(grep -i "GAME_APP_VER" src/Constants.h | cut -d'"' -f2)

make rpi BUILD_SDL2=1 RELEASE=1

# ── Download assets ──

# Texture pack (classicube.zip only — default.zip requires C-level image
# patching that can't be replicated in shell, and shipping an incomplete
# default.zip blocks classicube.zip from loading)
mkdir -p texpacks
wget -q --show-progress "${CC_CDN}/default.zip" -O texpacks/classicube.zip

# Music
mkdir -p audio
declare -A MUSIC=(
    ["calm1.ogg"]="50a59a4f56e4046701b758ddbb1c1587efa4cadf"
    ["calm2.ogg"]="74da65c99aa578486efa7b69983d3533e14c0d6e"
    ["calm3.ogg"]="14ae57a6bce3d4254daa8be2b098c2d99743cc3f"
    ["hal1.ogg"]="df1ff11b79757432c5c3f279e5ecde7b63ceda64"
    ["hal2.ogg"]="ceaaaa1d57dfdfbb0bd4da5ea39628b42897a687"
    ["hal3.ogg"]="dd85fb564e96ee2dbd4754f711ae9deb08a169f9"
    ["hal4.ogg"]="5e7d63e75c6e042f452bc5e151276911ef92fed8"
)
for name in "${!MUSIC[@]}"; do
    download_mojang "${MUSIC[$name]}" "audio/${name}"
done

# Sound effects → audio/default.zip
echo "Building audio/default.zip..."
SND_TMP=$(mktemp -d)
declare -A SOUNDS=(
    ["dig_cloth1.wav"]="5fd568d724ba7d53911b6cccf5636f859d2662e8"
    ["dig_cloth2.wav"]="56c1d0ac0de2265018b2c41cb571cc6631101484"
    ["dig_cloth3.wav"]="9c63f2a3681832dc32d206f6830360bfe94b5bfc"
    ["dig_cloth4.wav"]="55da1856e77cfd31a7e8c3d358e1f856c5583198"
    ["dig_grass1.wav"]="41cbf5dd08e951ad65883854e74d2e034929f572"
    ["dig_grass2.wav"]="86cb1bb0c45625b18e00a64098cd425a38f6d3f2"
    ["dig_grass3.wav"]="f7d7e5c7089c9b45fa5d1b31542eb455fad995db"
    ["dig_grass4.wav"]="c7b1005d4926f6a2e2387a41ab1fb48a72f18e98"
    ["dig_gravel1.wav"]="e8b89f316f3e9989a87f6e6ff12db9abe0f8b09f"
    ["dig_gravel2.wav"]="c3b3797d04cb9640e1d3a72d5e96edb410388fa3"
    ["dig_gravel3.wav"]="48f7e1bb098abd36b9760cca27b9d4391a23de26"
    ["dig_gravel4.wav"]="7bf3553a4fe41a0078f4988a13d6e1ed8663ef4c"
    ["dig_sand1.wav"]="9e59c3650c6c3fc0a475f1b753b2fcfef430bf81"
    ["dig_sand2.wav"]="0fa4234797f336ada4e3735e013e44d1099afe57"
    ["dig_sand3.wav"]="c75589cc0087069f387de127dd1499580498738e"
    ["dig_sand4.wav"]="37afa06f97d58767a1cd1382386db878be1532dd"
    ["dig_snow1.wav"]="e9bab7d3d15541f0aaa93fad31ad37fd07e03a6c"
    ["dig_snow2.wav"]="5887d10234c4f244ec5468080412f3e6ef9522f3"
    ["dig_snow3.wav"]="a4bc069321a96236fde04a3820664cc23b2ea619"
    ["dig_snow4.wav"]="e26fa3036cdab4c2264ceb19e1cd197a2a510227"
    ["dig_stone1.wav"]="4e094ed8dfa98656d8fec52a7d20c5ee6098b6ad"
    ["dig_stone2.wav"]="9c92f697142ae320584bf64c0d54381d59703528"
    ["dig_stone3.wav"]="8f23c02475d388b23e5faa680eafe6b991d7a9d4"
    ["dig_stone4.wav"]="363545a76277e5e47538b2dd3a0d6aa4f7a87d34"
    ["dig_wood1.wav"]="9bc2a84d0aa98113fc52609976fae8fc88ea6333"
    ["dig_wood2.wav"]="98102533e6085617a2962157b4f3658f59aea018"
    ["dig_wood3.wav"]="45b2aef7b5049e81b39b58f8d631563fadcc778b"
    ["dig_wood4.wav"]="dc66978374a46ab2b87db6472804185824868095"
    ["dig_glass1.wav"]="7274a2231ed4544a37e599b7b014e589e5377094"
    ["dig_glass2.wav"]="87c47bda3645c68f18a49e83cbf06e5302d087ff"
    ["dig_glass3.wav"]="ad7d770b7fff3b64121f75bd60cecfc4866d1cd6"
)
declare -A DOWNLOADED_HASHES
for name in "${!SOUNDS[@]}"; do
    hash="${SOUNDS[$name]}"
    if [[ -z "${DOWNLOADED_HASHES[$hash]}" ]]; then
        download_mojang "$hash" "${SND_TMP}/${name}"
        DOWNLOADED_HASHES[$hash]="${SND_TMP}/${name}"
    else
        cp "${DOWNLOADED_HASHES[$hash]}" "${SND_TMP}/${name}"
    fi
done
for mat in cloth grass gravel sand snow stone wood; do
    for i in 1 2 3 4; do
        [ -f "${SND_TMP}/dig_${mat}${i}.wav" ] && \
            cp "${SND_TMP}/dig_${mat}${i}.wav" "${SND_TMP}/step_${mat}${i}.wav"
    done
done
(cd "$SND_TMP" && zip -q "${OLDPWD}/audio/default.zip" *.wav)
rm -rf "$SND_TMP"

# ── Compose the DEB package ──

cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
INSTALL_DIR="/usr/local/games/classic-cube"

mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/texpacks
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/audio
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/plugins
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/maps
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/logs
mkdir -p $PACKAGE_NAME${INSTALL_DIR}/texturecache
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary & Data files
cp ClassiCube/ClassiCube $PACKAGE_NAME${INSTALL_DIR}/
cp ClassiCube/license.txt $PACKAGE_NAME${INSTALL_DIR}/ 2>/dev/null || true
cp pkg/options.txt $PACKAGE_NAME${INSTALL_DIR}/
cp pkg/fontscache.txt $PACKAGE_NAME${INSTALL_DIR}/
cp pkg/default.cw $PACKAGE_NAME${INSTALL_DIR}/maps/

# Assets
cp ClassiCube/texpacks/classicube.zip $PACKAGE_NAME${INSTALL_DIR}/texpacks/
cp ClassiCube/audio/*.ogg $PACKAGE_NAME${INSTALL_DIR}/audio/
cp ClassiCube/audio/default.zip $PACKAGE_NAME${INSTALL_DIR}/audio/

# Desktop and Icon
sudo tee $PACKAGE_NAME/usr/share/applications/classic-cube.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Classic Cube
Comment=Fun with Blocks
Path=${INSTALL_DIR}
Exec=env SDL_GAMECONTROLLERCONFIG="03000000412300003680000001010000,Arduino Leonardo,a:b0,b:b1,x:b3,y:b4,back:b10,start:b11,leftshoulder:b7,rightshoulder:b6,dpup:-a1,dpdown:+a1,dpleft:-a0,dpright:+a0,platform:Linux," ${INSTALL_DIR}/ClassiCube ${INSTALL_DIR}/maps/default.cw
Icon=classic-cube
Terminal=false
Categories=Game;
EOF
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/classic-cube.png

rm -rf ClassiCube/

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME