#!/bin/bash

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="supertux2"
VERSION="0.6.3"

# Upstream (Debian bookworm) package + revision used as source material.
# We don't build SuperTux from source: we reuse the official prebuilt
# binary and data files and repackage them with our own icon/config.
DEB_VERSION="0.6.3-2"
POOL_URL="http://deb.debian.org/debian/pool/main/s/supertux"
BIN_DEB="supertux_${DEB_VERSION}_${TARGET_ARCH}.deb"
DATA_DEB="supertux-data_${DEB_VERSION}_all.deb"

WORK_DIR="$CURRENT_DIR/_supertux2-build-work"

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "ERROR: missing icon at $CURRENT_DIR/pkg/icon.png"
    exit 1
fi

if [ ! -f "$CURRENT_DIR/pkg/config" ]; then
    echo "ERROR: missing default config at $CURRENT_DIR/pkg/config"
    exit 1
fi

command -v dpkg-deb >/dev/null 2>&1 || { echo "ERROR: se requiere 'dpkg-deb'"; exit 1; }
command -v wget >/dev/null 2>&1 || { echo "ERROR: se requiere 'wget'"; exit 1; }
if ! command -v convert >/dev/null 2>&1; then
    sudo apt-get install -y imagemagick || true
fi
command -v convert >/dev/null 2>&1 || { echo "ERROR: se requiere 'convert' (sudo apt-get install -y imagemagick)"; exit 1; }

# ── Descargar los paquetes oficiales de Debian (binario + datos) ──
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/downloads"

wget -q --show-progress -O "$WORK_DIR/downloads/$BIN_DEB" "$POOL_URL/$BIN_DEB" || exit 1
wget -q --show-progress -O "$WORK_DIR/downloads/$DATA_DEB" "$POOL_URL/$DATA_DEB" || exit 1

# ── Descomprimir y reutilizar su contenido ──
mkdir -p "$WORK_DIR/extract/bin" "$WORK_DIR/extract/data"
dpkg-deb -x "$WORK_DIR/downloads/$BIN_DEB" "$WORK_DIR/extract/bin" || exit 1
dpkg-deb -x "$WORK_DIR/downloads/$DATA_DEB" "$WORK_DIR/extract/data" || exit 1

# ── Ensamblar el paquete DEB ──
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"

cp -R "$CURRENT_DIR/pkg/DEBIAN/." "$PACKAGE_NAME/DEBIAN/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

# Reutilizar tal cual los archivos oficiales (binario, datos, .desktop,
# documentacion, man page, appdata...). El binario espera sus datos en
# share/games/supertux2, ruta que ya trae el paquete de datos.
mkdir -p "$PACKAGE_NAME/usr"
cp -a "$WORK_DIR/extract/bin/usr/." "$PACKAGE_NAME/usr/"
cp -a "$WORK_DIR/extract/data/usr/." "$PACKAGE_NAME/usr/"

# Eliminar los iconos que trae el paquete oficial (pixmaps + hicolor):
# se reemplazan por el icono personalizado.
rm -rf "$PACKAGE_NAME/usr/share/icons" "$PACKAGE_NAME/usr/share/pixmaps"

# Icono personalizado. El .desktop original ya usa "Icon=supertux2", asi
# que basta con instalarlo con ese nombre (no hace falta editar el .desktop).
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"
install -Dm 644 "$CURRENT_DIR/pkg/icon.png" \
    "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/supertux2.png"

# El motor tambien trae sus propios iconos internos (usados en tiempo de
# ejecucion como icono de ventana, ademas de assets para instaladores de
# otras plataformas). Se sustituyen todos por el icono personalizado.
ENGINE_ICONS_DIR="$PACKAGE_NAME/usr/share/games/supertux2/images/engine/icons"
if [ -d "$ENGINE_ICONS_DIR" ]; then
    convert "$CURRENT_DIR/pkg/icon.png" -resize 48x48 "$ENGINE_ICONS_DIR/supertux.png"
    convert "$CURRENT_DIR/pkg/icon.png" -resize 256x256 "$ENGINE_ICONS_DIR/supertux-256x256.png"
    convert "$CURRENT_DIR/pkg/icon.png" -resize 256x256 "$ENGINE_ICONS_DIR/supertux.ico"
    convert "$CURRENT_DIR/pkg/icon.png" -resize 256x256 "$ENGINE_ICONS_DIR/supertux.xpm"
    [ -f "$ENGINE_ICONS_DIR/old/supertux-256x256.png" ] && \
        convert "$CURRENT_DIR/pkg/icon.png" -resize 256x256 "$ENGINE_ICONS_DIR/old/supertux-256x256.png"
    [ -f "$ENGINE_ICONS_DIR/old/supertux2-256x256.png" ] && \
        convert "$CURRENT_DIR/pkg/icon.png" -resize 256x256 "$ENGINE_ICONS_DIR/old/supertux2-256x256.png"
    rm -f "$ENGINE_ICONS_DIR/supertux.icns"
fi

# Configuracion por defecto (perfil GamerCard: 720x720 fullscreen) dentro
# del home de la consola.
install -Dm 644 "$CURRENT_DIR/pkg/config" \
    "$PACKAGE_NAME/home/gamercard/.local/share/supertux2/config"

rm -rf "$WORK_DIR"

# Package DEB file
chmod 755 "$PACKAGE_NAME/DEBIAN/postinst"
chmod 755 "$PACKAGE_NAME/DEBIAN/postrm"
if command -v fakeroot >/dev/null; then
    fakeroot dpkg-deb --build --root-owner-group "$PACKAGE_NAME"
else
    sudo chown -R root:root "$PACKAGE_NAME"
    dpkg-deb --build --root-owner-group "$PACKAGE_NAME"
fi
rm -rf "$PACKAGE_NAME"

echo "Built ${PACKAGE_NAME}.deb"
