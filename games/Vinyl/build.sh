#!/bin/bash -e
#
# build-vinyl-deb.sh - Script para construir el paquete .deb de Vinyl
#
# Uso: ./build-vinyl-deb.sh [--clean]
#   --clean  Elimina los artefactos de construcción previos antes de empaquetar
#

REPO_URL="https://github.com/libredeb/vinyl.git"
APP_ID="io.github.libredeb.vinyl"
PKG_NAME="vinyl"
PKG_VERSION="0.1.1"
PKG_REVISION="1"
ARCH=$(dpkg --print-architecture)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_ICON="${SCRIPT_DIR}/pkg/icon.png"
WORK_DIR="${SCRIPT_DIR}/_vinyl-deb-work"
SRC_DIR="${WORK_DIR}/vinyl"
PKG_ROOT="${WORK_DIR}/${PKG_NAME}_${PKG_VERSION}-${PKG_REVISION}_${ARCH}"
OUTPUT_DIR="${SCRIPT_DIR}"

# --- Verificar dependencias de construcción ---
check_deps() {
    local missing=()
    local deps=(
        git meson ninja-build valac dpkg-dev
        libgee-0.8-dev libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev
        libtagc0-dev libsqlite3-dev libgstreamer1.0-dev
        libgstreamer-plugins-base1.0-dev libgdk-pixbuf-2.0-dev
        gettext python3 python3-wheel python3-setuptools
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

# --- Clonar el repositorio ---
clone_repo() {
    echo ">>> Clonando repositorio ${REPO_URL}..."
    mkdir -p "${WORK_DIR}"
    git clone --depth=1 "${REPO_URL}" "${SRC_DIR}"
    echo "    Clonado en: ${SRC_DIR}"
}

# --- Compilar el proyecto ---
build() {
    echo ">>> Compilando Vinyl..."
    cd "${SRC_DIR}"
    meson setup build --prefix=/usr
    ninja -C build
}

# --- Instalar en el directorio raíz del paquete (DESTDIR) ---
install_to_pkg() {
    echo ">>> Instalando en DESTDIR=${PKG_ROOT}..."
    cd "${SRC_DIR}"
    DESTDIR="${PKG_ROOT}" ninja -C build install
}

# --- Modificar el .desktop (categoría Game) ---
patch_desktop() {
    echo ">>> Modificando archivo .desktop..."
    local desktop_file="${PKG_ROOT}/usr/share/applications/${APP_ID}.desktop"
    if [ ! -f "${desktop_file}" ]; then
        desktop_file="${PKG_ROOT}/usr/share/applications/${PKG_NAME}.desktop"
    fi

    if [ -f "${desktop_file}" ]; then
        sed -i 's/^Categories=.*/Categories=Game;/' "${desktop_file}"
        echo "    Categoría cambiada a Game en: $(basename "${desktop_file}")"
    else
        echo "ADVERTENCIA: No se encontró archivo .desktop para modificar"
    fi
}

# --- Reemplazar iconos por el icono custom ---
patch_icons() {
    echo ">>> Reemplazando iconos por icono custom..."

    # Eliminar todos los iconos originales de la app
    find "${PKG_ROOT}/usr/share/icons/hicolor" -type f -name "${APP_ID}.*" -delete

    # Instalar el icono custom como PNG en scalable/apps
    mkdir -p "${PKG_ROOT}/usr/share/icons/hicolor/scalable/apps"
    cp "${CUSTOM_ICON}" "${PKG_ROOT}/usr/share/icons/hicolor/scalable/apps/${APP_ID}.png"
    echo "    Icono custom instalado en: hicolor/scalable/apps/${APP_ID}.png"
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
Depends: libgee-0.8-2, libsdl2-2.0-0, libsdl2-image-2.0-0, libsdl2-ttf-2.0-0, libtagc0, libsqlite3-0, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, libgdk-pixbuf-2.0-0, gstreamer1.0-plugins-good, gstreamer1.0-plugins-base
Maintainer: LibreDeb Team <contact@libredeb.org>
Homepage: https://github.com/libredeb/vinyl
Description: Browse and play your music library
 Vinyl is a lightweight music player built with SDL2 and GStreamer.
 It provides a simple and elegant interface to browse, manage
 and play your local music collection and online radio stations.
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
Upstream-Name: Vinyl
Upstream-Contact: LibreDeb Team <contact@libredeb.org>
Source: https://github.com/libredeb/vinyl

Files: *
Copyright: 2024 LibreDeb Team
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
    echo "=== Construyendo paquete .deb para Vinyl ${PKG_VERSION} ==="
    echo ""

    check_deps
    check_icon
    clean
    clone_repo
    build
    install_to_pkg
    patch_desktop
    patch_icons
    create_debian_control
    build_deb

    # Limpiar directorio de trabajo
    echo ">>> Limpiando directorio de trabajo..."
    rm -rf "${WORK_DIR}"

    echo "¡Listo!"
}

main "$@"