#!/bin/bash -e
#
# build-vinyl-deb.sh - Script para construir el paquete .deb de Quantum Storm
#
# Uso: ./build-vinyl-deb.sh [--clean]
#   --clean  Elimina los artefactos de construcción previos antes de empaquetar
#

APP_ID="tombsofmyra"
PKG_NAME="tombsofmyra"
PKG_VERSION="1.0.0"
PKG_REVISION="1"
ARCH=$(dpkg --print-architecture)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_ICON="${SCRIPT_DIR}/pkg/icon.png"
CUSTOM_DESKTOP="${SCRIPT_DIR}/pkg/tombsofmyra.desktop"
WORK_DIR="${SCRIPT_DIR}/_deb-work"
SRC_DIR="${SCRIPT_DIR}/opt/tombsofmyra"
PKG_ROOT="${WORK_DIR}/${PKG_NAME}_${PKG_VERSION}-${PKG_REVISION}_${ARCH}"
OUTPUT_DIR="${SCRIPT_DIR}"

# --- Verificar dependencias de construcción ---
check_deps() {
    local missing=()
    local deps=(
        debhelper g++ libsdl2-dev libsdl2-image-dev
        libsdl2-dev libsdl2-mixer-dev
    )
    for dep in "${deps[@]}"; do
        if ! dpkg -s "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Faltan dependencias de construcción:"
        printf '  %s\n' "${missing[@]}"
        echo ""
        echo "Instálalas con:"
        echo "  sudo apt-get install ${missing[*]}"
        exit 1
    fi
}

# --- Verificar que exista el icono custom ---
check_icon() {
    if [ ! -f "${CUSTOM_ICON}" ]; then
        echo "ERROR: No se encontró el icono custom en: ${CUSTOM_ICON}"
        echo "Coloca el archivo 'custom-icon.png' junto a este script."
        exit 1
    fi
}

# --- Limpiar construcción previa ---
clean() {
    echo ">>> Limpiando artefactos previos..."
    rm -rf "${WORK_DIR}"
}

# --- Copiar los archivos necesarios ---
copy_files() {
    echo ">>> Copiando archivos necesarios..."
    mkdir -p "${PKG_ROOT}/opt/tombsofmyra"
    mkdir -p "${PKG_ROOT}/usr/share/applications"
    mkdir -p "${PKG_ROOT}/usr/share/icons/hicolor/scalable/apps"
    cp -a "${SRC_DIR}/." "${PKG_ROOT}/opt/tombsofmyra/"
    cp -r "${CUSTOM_DESKTOP}" "${PKG_ROOT}/usr/share/applications/tombsofmyra.desktop"
    cp -r "${CUSTOM_ICON}" "${PKG_ROOT}/usr/share/icons/hicolor/scalable/apps/tombsofmyra.png"

}

# --- Crear la estructura DEBIAN ---
create_debian_control() {
    echo ">>> Creando archivos de control del paquete..."
    mkdir -p "${PKG_ROOT}/DEBIAN"

    # --- control ---
    cat > "${PKG_ROOT}/DEBIAN/control" << EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}-${PKG_REVISION}
Section: games
Priority: optional
Architecture: ${ARCH}
Maintainer: Jochen Heizmann <jochen@asylumsquare.com>
Depends: libc6:arm64 (>= 2.28), libstdc++6:arm64, libopenal1:arm64, libopengl0:arm64, libasound2:arm64, libsndio7.0:arm64, libbsd0:arm64, libmd0:arm64
Description: A turn based dungeon creawler game.
 Descend into the cursed tombs of Myra and free the souls 
 of ancient warriors in this turn-based 
 puzzle dungeon crawler game.

EOF

    # --- postinst ---
    cat > "${PKG_ROOT}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
if [ "$1" = "configure" ]; then
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
    fi
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database -q /usr/share/applications 2>/dev/null || true
    fi
fi

chown -R gamercard:gamercard "/opt/tombsofmyra"
    chmod +x "/opt/tombsofmyra/TombsOfMyra"

exit 0
EOF
    chmod 755 "${PKG_ROOT}/DEBIAN/postinst"

    # --- postrm ---
    cat > "${PKG_ROOT}/DEBIAN/postrm" << 'EOF'
#!/bin/bash
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    if command -v gtk-update-icon-cache &>/dev/null; then
        gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor 2>/dev/null || true
    fi
    if command -v update-desktop-database &>/dev/null; then
        update-desktop-database -q /usr/share/applications 2>/dev/null || true
    fi
fi
exit 0
EOF
    chmod 755 "${PKG_ROOT}/DEBIAN/postrm"

    # --- copyright ---
    cat > "${PKG_ROOT}/DEBIAN/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: tombsofmyra
Upstream-Contact: Jochen Heizmann <jochen@asylumsquare.com>
Source: https://github.com/jochenheizmann/tombsofmyra

Files: *
Copyright: 2026 Jochen Heizmann
License: GPL-3+
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 .
 On Debian systems, the complete text of the GNU General Public License
 version 3 can be found in "/usr/share/common-licenses/GPL-3".
EOF
}

# --- Construir el .deb ---
build_deb() {
    echo ">>> Construyendo paquete .deb..."
    dpkg-deb --build --root-owner-group "${PKG_ROOT}"
    local deb_file="${PKG_ROOT}.deb"
    local final_deb="${OUTPUT_DIR}/$(basename "${deb_file}")"

    # Mover el .deb al directorio del script
    mv "${deb_file}" "${final_deb}"

    if [ -f "${final_deb}" ]; then
        echo ""
        echo "=========================================="
        echo " Paquete generado exitosamente!"
        echo " ${final_deb}"
        echo "=========================================="
        echo ""
        echo "Para instalar:"
        echo "  sudo dpkg -i ${final_deb}"
        echo ""
        echo "Para verificar el contenido:"
        echo "  dpkg-deb -c ${final_deb}"
        echo ""
    else
        echo "ERROR: No se pudo generar el paquete .deb"
        exit 1
    fi
}

# --- Main ---
main() {
    echo "=== Construyendo paquete .deb para Toms of Myra ${PKG_VERSION} ==="
    echo ""

    check_deps
    check_icon
    clean

    copy_files
    
    create_debian_control
    build_deb

    # Limpiar directorio de trabajo
    echo ">>> Limpiando directorio de trabajo..."
    rm -rf "${WORK_DIR}"

    echo "¡Listo!"
}

main "$@"