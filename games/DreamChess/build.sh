#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="dreamchess"
VERSION="0.3.0"
SOURCE_URL="https://github.com/dreamchess/dreamchess/archive/refs/tags/${VERSION}.tar.gz"
SOURCE_DIR="dreamchess-${VERSION}"

# Build dependencies.
# libglew-dev / mesa GL are required by CMake even if the upstream README omits them.
sudo apt-get install -y gcc cmake bison flex gettext \
    libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
    libexpat1-dev libfreetype-dev \
    libepoxy-dev libgl1-mesa-dev libglu1-mesa-dev pkg-config wget \
    || echo "WARNING: apt-get failed; continuing with already installed packages"

# ── Source ──
rm -rf "$SOURCE_DIR" "${VERSION}.tar.gz"
wget -q --show-progress -O "${VERSION}.tar.gz" "$SOURCE_URL" || exit 1
tar -xzf "${VERSION}.tar.gz" || exit 1
rm -f "${VERSION}.tar.gz"

# ── GamerCard gamepad + Wayland/EGL (libepoxy instead of GLEW) ──
python3 "$CURRENT_DIR/pkg/patch-gamepad.py" "$SOURCE_DIR" || exit 1
python3 "$CURRENT_DIR/pkg/patch-gl.py" "$SOURCE_DIR" || exit 1

# ── Strip broken PNG color profiles (libpng iCCP warnings) ──
python3 "$CURRENT_DIR/pkg/strip-png-icc.py" \
    "$SOURCE_DIR/dreamchess/data" \
    "$SOURCE_DIR/dreamchess/desktop" \
    "$CURRENT_DIR/pkg/icon.png" || exit 1

# ── Build ──
# Pi Zero 2 W rev 1.0 (Cortex-A53) + Mesa GLVND, Wayland, PipeWire
mkdir -p "$SOURCE_DIR/build"
cd "$SOURCE_DIR/build" || exit 1

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DOpenGL_GL_PREFERENCE=GLVND \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_C_FLAGS="-O2 -mcpu=cortex-a53 -ftree-vectorize -pipe" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,-O1 -Wl,--as-needed" || exit 1

cmake --build . -j"$(nproc)" || exit 1

# ── Compose the DEB package ──
cd "$CURRENT_DIR" || exit 1
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"

cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

DESTDIR="$CURRENT_DIR/$PACKAGE_NAME" cmake --install "$SOURCE_DIR/build" || exit 1

# Binary lives under /usr/lib so the wrapper can export Wayland/PipeWire/gamepad
mkdir -p "$PACKAGE_NAME/usr/lib/dreamchess"
mv "$PACKAGE_NAME/usr/bin/dreamchess" "$PACKAGE_NAME/usr/lib/dreamchess/dreamchess"
install -Dm 755 pkg/dreamchess "$PACKAGE_NAME/usr/bin/dreamchess"
install -Dm 644 pkg/options.xml "$PACKAGE_NAME/usr/share/dreamchess/options.xml"

# Drop upstream hicolor icons and install the custom one
rm -rf "$PACKAGE_NAME/usr/share/icons"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"
install -Dm 644 pkg/icon.png "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/dreamchess.png"

if [ -d "$PACKAGE_NAME/usr/share/man" ]; then
    find "$PACKAGE_NAME/usr/share/man" -type f -name '*.[0-9]' -exec gzip -nf {} +
fi

strip --strip-unneeded \
    "$PACKAGE_NAME/usr/lib/dreamchess/dreamchess" \
    "$PACKAGE_NAME/usr/bin/dreamer" 2>/dev/null || true

rm -rf "$SOURCE_DIR"
rm -rf "$CURRENT_DIR/pkg/__pycache__"

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
if command -v fakeroot >/dev/null; then
    fakeroot dpkg-deb --build "$PACKAGE_NAME"
else
    sudo chown -R root:root "$PACKAGE_NAME"
    dpkg-deb --build "$PACKAGE_NAME"
fi
rm -rf "$PACKAGE_NAME"
