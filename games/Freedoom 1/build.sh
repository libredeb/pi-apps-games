#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="freedoom1"
VERSION="0.13.0"
DEBIAN_RELEASE="3"
DEBIAN_TARBALL="freedoom_${VERSION}-${DEBIAN_RELEASE}.debian.tar.xz"
DEBIAN_URL="http://ftp.de.debian.org/debian/pool/main/f/freedoom/${DEBIAN_TARBALL}"

MAKE_OPTS=(
    ADOCOPTS=""
    ASCIIDOC="asciidoctor"
    ASCIIDOC_MAN="asciidoctor -b manpage"
    VERSION="$VERSION"
)

# Build dependencies
sudo apt-get install -y \
    curl xz-utils \
    make git patch cmake build-essential pkg-config \
    asciidoctor deutex \
    python3 python3-pil \
    ruby-asciidoctor-pdf \
    fluidsynth libfluidsynth-dev libmad0-dev libportmidi-dev \
    libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev libsdl2-net-dev \
    libvorbis-dev libzip-dev zipcmp zipmerge ziptool libxmp-dev || exit 1

# deutex lives in /usr/games on Debian
export PATH="/usr/games:${PATH}"

# --- Build Freedoom Phase 1 WAD ---
rm -rf freedoom "$DEBIAN_TARBALL"
git clone --depth 1 --branch "v${VERSION}" https://github.com/freedoom/freedoom.git || exit 1
cd freedoom || exit 1

curl -L -o "../${DEBIAN_TARBALL}" "${DEBIAN_URL}" || exit 1
tar -xJf "../${DEBIAN_TARBALL}" || exit 1

for patch in debian/patches/*.patch; do
    case "$(basename "$patch")" in
        0171-*) continue ;;  # keep /usr/share/icons layout for our custom launcher
    esac
    patch -p1 -N < "$patch" || exit 1
done

make "${MAKE_OPTS[@]}" wads/freedoom1.wad \
    NEWS.html README.html \
    manual/freedoom-manual-en.pdf \
    manual/freedoom-manual-es.pdf \
    manual/freedoom-manual-fr.pdf || exit 1

sed -e '/googleapis.com/d' -i NEWS.html README.html

# --- Build dsda-doom engine (autonomous package) ---
cd "$CURRENT_DIR" || exit 1
rm -rf dsda-doom
git clone --depth 1 https://github.com/kraflab/dsda-doom.git || exit 1
mkdir -p dsda-doom/build
cmake -S dsda-doom/prboom2 -B dsda-doom/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-mcpu=cortex-a53" \
    -DCMAKE_CXX_FLAGS="-mcpu=cortex-a53" || exit 1
cmake --build dsda-doom/build -j"$(nproc)" || exit 1

# --- Compose the DEB package ---
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
INSTALL_ROOT="$CURRENT_DIR/$PACKAGE_NAME/usr"
GAME_DIR="$INSTALL_ROOT/share/freedoom1"

rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"
mkdir -p "$GAME_DIR"
mkdir -p "$INSTALL_ROOT/share/applications"
mkdir -p "$INSTALL_ROOT/share/icons/hicolor/scalable/apps"

cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

# Engine + WAD (self-contained, like quake1)
install -Dm 755 dsda-doom/build/dsda-doom "$GAME_DIR/dsda-doom"
install -Dm 644 freedoom/wads/freedoom1.wad "$GAME_DIR/freedoom1.wad"
if [ -f dsda-doom/build/dsda-doom.wad ]; then
    install -Dm 644 dsda-doom/build/dsda-doom.wad "$GAME_DIR/dsda-doom.wad"
fi

# Preset (Hyperpixel 720x720 + Leonardo gamepad)
install -Dm 644 pkg/dsda-doom.cfg "$GAME_DIR/dsda-doom.cfg"
install -Dm 755 pkg/freedoom1 "$GAME_DIR/freedoom1"

# Documentation
install -Dm 644 freedoom/CREDITS freedoom/CREDITS-MUSIC \
    freedoom/NEWS.html freedoom/README.html \
    -t "$INSTALL_ROOT/share/doc/freedoom"
gzip -nf "$INSTALL_ROOT/share/doc/freedoom/CREDITS"
gzip -nf "$INSTALL_ROOT/share/doc/freedoom/CREDITS-MUSIC"
install -Dm 644 freedoom/manual/freedoom-manual-en.pdf \
    freedoom/manual/freedoom-manual-es.pdf \
    freedoom/manual/freedoom-manual-fr.pdf \
    -t "$INSTALL_ROOT/share/doc/freedoom"
gzip -nf "$INSTALL_ROOT/share/doc/freedoom/freedoom-manual-"*.pdf

install -Dm 644 freedoom/debian/copyright "$INSTALL_ROOT/share/doc/freedoom/copyright"

# Custom launcher and icon
tee "$INSTALL_ROOT/share/applications/freedoom1.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Freedoom 1
Comment=Battle monsters in four 9-level episodes
Exec=/usr/share/freedoom1/freedoom1
Icon=freedoom1
Terminal=false
Categories=Game;ActionGame;
Keywords=first;person;shooter;doom;freedoom;
StartupNotify=false
EOF
cp pkg/icon.png "$INSTALL_ROOT/share/icons/hicolor/scalable/apps/freedoom1.png"

rm -rf freedoom dsda-doom "$CURRENT_DIR/$DEBIAN_TARBALL"

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
sudo chown -R root:root "$PACKAGE_NAME"
dpkg-deb --build "$PACKAGE_NAME"
sudo rm -rf "$PACKAGE_NAME"
