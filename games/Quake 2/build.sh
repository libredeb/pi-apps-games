#!/bin/bash
set -euo pipefail

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

TARGET_ARCH=$(get_debian_arch)
GAME="quake2"
VERSION="8.70"
YQ2_TAG="QUAKE2_8_70"
# Official Quake II demo 3.14 (the one Yamagi documents). Not the 1997 q2_test.
DEMO_URL="https://deponie.yamagi.org/quake2/idstuff/q2-314-demo-x86.exe"
DEMO_URL_FALLBACK="https://ftp.gwdg.de/pub/misc/ftp.idsoftware.com/idstuff/quake2/q2-314-demo-x86.exe"
DEMO_EXE_MD5="4d1cd4618e80a38db59304132ea0856c"
PAK0_MD5="27d77240466ec4f3253256832b54db8a"

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "error: pkg/icon.png is missing" >&2
    exit 1
fi

# Build dependencies (SDL2: Bookworm has no SDL3; 8.70 still supports SDL2)
# OpenAL/cURL are optional in Yamagi and skipped to keep runtime deps small
# on the Pi Zero 2 W. Mesa on Bookworm cannot create a GLES1 EGL context
# (legacy Pi driver only), so we ship GL1 + software fallback.
sudo apt-get install -y \
    build-essential git make pkg-config python3 \
    libsdl2-dev libgl1-mesa-dev \
    curl unzip ca-certificates || exit 1

rm -rf yquake2
git clone --depth 1 --branch "$YQ2_TAG" https://github.com/yquake2/yquake2.git yquake2 \
    || { echo "error: could not clone Yamagi Quake II ($YQ2_TAG)" >&2; exit 1; }

make -C yquake2 -j"$(nproc)" \
    WITH_SDL3=no \
    WITH_OPENAL=no \
    WITH_CURL=no \
    WITH_RPATH=no \
    WITH_SYSTEMWIDE=yes \
    WITH_SYSTEMDIR=/usr/share/quake2 \
    CFLAGS="-O2 -Wall -pipe -fomit-frame-pointer -mcpu=cortex-a53" \
    client game ref_gl1 ref_soft

RELEASE_DIR="$CURRENT_DIR/yquake2/release"
if [ ! -x "$RELEASE_DIR/quake2" ] || [ ! -f "$RELEASE_DIR/ref_gl1.so" ] || [ ! -f "$RELEASE_DIR/ref_soft.so" ] || [ ! -f "$RELEASE_DIR/baseq2/game.so" ]; then
    echo "error: Yamagi build did not produce quake2 / ref_gl1.so / ref_soft.so / baseq2/game.so" >&2
    exit 1
fi

# Compose the DEB package
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
INSTALL_ROOT="$CURRENT_DIR/$PACKAGE_NAME/usr"
GAME_DIR="$INSTALL_ROOT/share/quake2"

rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"
mkdir -p "$INSTALL_ROOT/bin"
mkdir -p "$GAME_DIR/baseq2"
mkdir -p "$INSTALL_ROOT/share/applications"
mkdir -p "$INSTALL_ROOT/share/icons/hicolor/scalable/apps"
mkdir -p "$INSTALL_ROOT/share/doc/quake2"

cp -R pkg/DEBIAN "$PACKAGE_NAME/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

# Engine: binaries must live together (packaging guide)
install -Dm 755 "$RELEASE_DIR/quake2" "$GAME_DIR/quake2"
install -Dm 644 "$RELEASE_DIR/ref_gl1.so" "$GAME_DIR/ref_gl1.so"
install -Dm 644 "$RELEASE_DIR/ref_soft.so" "$GAME_DIR/ref_soft.so"
install -Dm 644 "$RELEASE_DIR/baseq2/game.so" "$GAME_DIR/baseq2/game.so"
install -Dm 644 yquake2/stuff/yq2.cfg "$GAME_DIR/baseq2/yq2.cfg"
install -Dm 644 pkg/autoexec.cfg "$GAME_DIR/baseq2/autoexec.cfg"
install -Dm 755 pkg/quake2 "$INSTALL_ROOT/bin/quake2"
install -Dm 644 yquake2/LICENSE "$INSTALL_ROOT/share/doc/quake2/copyright"

# Official demo 3.14 (self-extracting ZIP). Do not apply the 3.20 patch.
TMP_DEMO="$(mktemp /tmp/q2-314-demo.XXXXXX.exe)"
if ! curl -L --fail -A "Mozilla/5.0" -o "$TMP_DEMO" "$DEMO_URL"; then
    echo "Primary demo download failed, trying fallback mirror" >&2
    curl -L --fail -A "Mozilla/5.0" -o "$TMP_DEMO" "$DEMO_URL_FALLBACK"
fi
DEMO_GOT_MD5="$(md5sum "$TMP_DEMO" | awk '{print $1}')"
if [ "$DEMO_GOT_MD5" != "$DEMO_EXE_MD5" ]; then
    echo "error: demo installer MD5 mismatch (got $DEMO_GOT_MD5, expected $DEMO_EXE_MD5)" >&2
    exit 1
fi

python3 - "$TMP_DEMO" "$GAME_DIR/baseq2" "$PAK0_MD5" <<'PY'
import hashlib, sys, zipfile
from pathlib import Path

exe, dest, expect = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
dest.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(exe) as zf:
    names = zf.namelist()
    pak_name = next(n for n in names if n.replace("\\", "/").lower().endswith("baseq2/pak0.pak"))
    pak = zf.read(pak_name)
    got = hashlib.md5(pak).hexdigest()
    if got != expect:
        sys.exit(f"pak0.pak MD5 mismatch (got {got}, expected {expect})")
    (dest / "pak0.pak").write_bytes(pak)
    for name in names:
        norm = name.replace("\\", "/")
        if "/baseq2/players/" not in norm.lower() or norm.endswith("/"):
            continue
        rel = norm.split("/baseq2/players/", 1)[1]
        out = dest / "players" / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(zf.read(name))
print("installed official demo pak0.pak and players/")
PY
rm -f "$TMP_DEMO"

# Fill any menu pics the demo might still omit (no-op if already in pak0).
python3 "$CURRENT_DIR/pkg/gen-missing-pics.py" \
    "$GAME_DIR/baseq2/pak0.pak" "$GAME_DIR/baseq2/pics"

# Desktop and icon
tee "$INSTALL_ROOT/share/applications/quake2.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Quake 2
Comment=Classic sci-fi first-person shooter
Exec=/usr/bin/quake2
Icon=quake2
Terminal=false
Categories=Game;ActionGame;
Keywords=quake;idsoftware;fps;shooter;retro;
StartupNotify=false
EOF
cp pkg/icon.png "$INSTALL_ROOT/share/icons/hicolor/scalable/apps/quake2.png"

rm -rf yquake2

chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
sudo chown -R root:root "$PACKAGE_NAME"
dpkg-deb --build "$PACKAGE_NAME"
sudo rm -rf "$PACKAGE_NAME"
