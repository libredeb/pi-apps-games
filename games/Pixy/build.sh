#!/bin/bash
set -eo pipefail

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="pixy"
ASSETS_DIR="$CURRENT_DIR/pkg/assets"
WORK_DIR="$CURRENT_DIR/_pixy-build-work"

# Cuanto contenido de la libreria de ejemplo se conserva, para mantener el
# .deb liviano: solo los primeros N artistas/albumes/temas (orden alfabetico).
MAX_ARTISTS=3
MAX_ALBUMS_PER_ARTIST=3
MAX_TRACKS_PER_ALBUM=5
# La consola no muestra mas resolucion que esta, así que las portadas/fotos
# de artista no necesitan pesar mas que una imagen de este tamaño.
COVER_MAX_DIM=720

if [ ! -f "$CURRENT_DIR/pkg/icon.png" ]; then
    echo "ERROR: missing icon at $CURRENT_DIR/pkg/icon.png"
    exit 1
fi

command -v unzip >/dev/null 2>&1 || { echo "ERROR: se requiere 'unzip' (sudo apt-get install -y unzip)"; exit 1; }
if ! command -v convert >/dev/null 2>&1; then
    sudo apt-get install -y imagemagick || true
fi
command -v convert >/dev/null 2>&1 || { echo "ERROR: se requiere 'convert' (sudo apt-get install -y imagemagick)"; exit 1; }

# ── Los dos ZIPs de origen no se versionan; deben colocarse manualmente ──
LIBRARY_ZIP="$ASSETS_DIR/library.zip"
if [ ! -f "$LIBRARY_ZIP" ]; then
    echo "ERROR: no se encontro $LIBRARY_ZIP"
    echo "       Coloca 'library.zip' (la libreria de musica de ejemplo) en $ASSETS_DIR"
    exit 1
fi

mapfile -t APP_ZIP_CANDIDATES < <(find "$ASSETS_DIR" -maxdepth 1 -type f -iname '*.zip' ! -iname 'library.zip')
if [ "${#APP_ZIP_CANDIDATES[@]}" -eq 0 ]; then
    echo "ERROR: no se encontro el zip de la app Pixy dentro de $ASSETS_DIR"
    exit 1
elif [ "${#APP_ZIP_CANDIDATES[@]}" -gt 1 ]; then
    echo "ERROR: hay mas de un candidato a zip de la app en $ASSETS_DIR; deja solo uno junto a library.zip:"
    printf '  %s\n' "${APP_ZIP_CANDIDATES[@]}"
    exit 1
fi
APP_ZIP="${APP_ZIP_CANDIDATES[0]}"

# ── Extraer el zip de la app en un directorio de trabajo temporal ──
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/app"
unzip -q "$APP_ZIP" -d "$WORK_DIR/app"

mapfile -t APP_ROOTS < <(find "$WORK_DIR/app" -mindepth 1 -maxdepth 1 -type d)
if [ "${#APP_ROOTS[@]}" -ne 1 ]; then
    echo "ERROR: se esperaba una unica carpeta raiz dentro de $(basename "$APP_ZIP")"
    exit 1
fi
APP_ROOT="${APP_ROOTS[0]}"

[ -f "$APP_ROOT/manual-install.sh" ] || { echo "ERROR: manual-install.sh no encontrado dentro del zip de la app"; exit 1; }
[ -f "$APP_ROOT/BUILD-INFO.txt" ] || { echo "ERROR: BUILD-INFO.txt no encontrado dentro del zip de la app"; exit 1; }

# La version se extrae directamente del contenido del zip (BUILD-INFO.txt),
# nunca se hardcodea en este script.
VERSION="$(grep -oP '^Version:\s*\K.+' "$APP_ROOT/BUILD-INFO.txt" | head -1)"
[ -n "$VERSION" ] || { echo "ERROR: no se pudo leer la version desde BUILD-INFO.txt"; exit 1; }

PAYLOAD_DIR="$APP_ROOT/payload"
[ -d "$PAYLOAD_DIR" ] || { echo "ERROR: no existe payload/ dentro del zip de la app"; exit 1; }

# El binario es el unico archivo de payload/ que no es ni .desktop ni icono.
mapfile -t RELEASE_BIN_CANDIDATES < <(find "$PAYLOAD_DIR" -maxdepth 1 -type f ! -iname '*.desktop' ! -iname '*.png')
if [ "${#RELEASE_BIN_CANDIDATES[@]}" -ne 1 ]; then
    echo "ERROR: no se pudo identificar de forma unica el binario dentro de payload/"
    exit 1
fi
RELEASE_BIN="${RELEASE_BIN_CANDIDATES[0]}"

DESKTOP_SRC="$(find "$PAYLOAD_DIR" -maxdepth 1 -type f -iname '*.desktop' | head -1)"
[ -n "$DESKTOP_SRC" ] || { echo "ERROR: no se encontro el archivo .desktop dentro de payload/"; exit 1; }

# ── Ensamblar el paquete DEB ──
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
rm -rf "$PACKAGE_NAME"
mkdir -p "$PACKAGE_NAME/DEBIAN"

cp -R "$CURRENT_DIR/pkg/DEBIAN/." "$PACKAGE_NAME/DEBIAN/"
sed -i "s/^Version: .*/Version: ${VERSION}/" "$PACKAGE_NAME/DEBIAN/control"

mkdir -p "$PACKAGE_NAME/usr/local/pixy/Pixy"
mkdir -p "$PACKAGE_NAME/usr/share/applications"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/64x64/apps"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps"

# Ejecutable: se renombra junto con el resto de rutas tecnicas, que pasan
# de "MusicPlayer" a "Pixy".
install -Dm 755 "$RELEASE_BIN" "$PACKAGE_NAME/usr/local/pixy/Pixy/Pixy"

# .desktop: se toma el del zip y se corrige (nombre, icono y rutas).
install -Dm 644 "$DESKTOP_SRC" "$PACKAGE_NAME/usr/share/applications/pixy.desktop"
sed -i \
    -e 's/^Name=.*/Name=Pixy/' \
    -e 's/^Icon=.*/Icon=pixy/' \
    -e "s|^Path=.*|Path=/usr/local/pixy/Pixy|" \
    -e "s|^Exec=.*|Exec=/usr/local/pixy/Pixy/Pixy|" \
    "$PACKAGE_NAME/usr/share/applications/pixy.desktop"

# Icono: un unico archivo (icon.png) para los 3 tamanos hicolor que espera
# Lightpad, reemplazando siempre a los que trae el zip de la app.
install -Dm 644 "$CURRENT_DIR/pkg/icon.png" "$PACKAGE_NAME/usr/share/icons/hicolor/64x64/apps/pixy.png"
install -Dm 644 "$CURRENT_DIR/pkg/icon.png" "$PACKAGE_NAME/usr/share/icons/hicolor/256x256/apps/pixy.png"
install -Dm 644 "$CURRENT_DIR/pkg/icon.png" "$PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/pixy.png"

# ── Libreria de musica de ejemplo ──
# Se extrae directamente en su destino final dentro del propio arbol del
# paquete: NUNCA se copia a un lugar comun para luego moverla, ya que eso
# duplicaria ~350 MB de audio sin necesidad.
MUSIC_DEST="$PACKAGE_NAME/home/gamercard/Music"
mkdir -p "$MUSIC_DEST"
unzip -q "$LIBRARY_ZIP" -d "$MUSIC_DEST"

# Basura de macOS que no debe llegar al paquete final.
find "$MUSIC_DEST" -depth -type d -iname '__MACOSX' -exec rm -rf {} +
find "$MUSIC_DEST" -type f -iname '.DS_Store' -delete

# ── Curar la libreria: solo los primeros N artistas, con sus primeros N
#     albumes, con sus primeros N temas (orden alfabetico/numerico). Las
#     portadas y fotos de artista de lo que se conserva NO se tocan aqui. ──
mapfile -t ARTIST_DIRS < <(find "$MUSIC_DEST" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
for artist_dir in "${ARTIST_DIRS[@]:$MAX_ARTISTS}"; do
    rm -rf "$artist_dir"
done

for artist_dir in "${ARTIST_DIRS[@]:0:$MAX_ARTISTS}"; do
    mapfile -t ALBUM_DIRS < <(find "$artist_dir" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
    for album_dir in "${ALBUM_DIRS[@]:$MAX_ALBUMS_PER_ARTIST}"; do
        rm -rf "$album_dir"
    done

    for album_dir in "${ALBUM_DIRS[@]:0:$MAX_ALBUMS_PER_ARTIST}"; do
        # Orden numerico por el numero de pista al inicio del nombre de
        # archivo (soporta "1 - Title.mp3", "10 - Title.mp3", "1 -Title.mp3"...).
        mapfile -t SORTED_TRACKS < <(
            find "$album_dir" -maxdepth 1 -type f -iname '*.mp3' -print0 \
                | while IFS= read -r -d '' track; do
                    track_num="$(grep -oE '^[0-9]+' <<<"$(basename "$track")")"
                    printf '%06d\t%s\n' "${track_num:-999999}" "$track"
                done \
                | LC_ALL=C sort -n -k1,1 -t $'\t' \
                | cut -f2-
        )
        for track in "${SORTED_TRACKS[@]:$MAX_TRACKS_PER_ALBUM}"; do
            rm -f "$track"
        done
    done
done

# ── Reducir portadas/fotos de artista a lo maximo que la consola puede
#     mostrar: nunca agranda, solo achica las que superan COVER_MAX_DIM. ──
find "$MUSIC_DEST" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0 \
    | while IFS= read -r -d '' img; do
        convert "$img" -resize "${COVER_MAX_DIM}x${COVER_MAX_DIM}>" -strip "$img"
    done

# El zip de origen trae permisos unix inconsistentes (algunos archivos
# quedan en 600); se normalizan para que siempre queden legibles.
find "$MUSIC_DEST" -type d -exec chmod 755 {} +
find "$MUSIC_DEST" -type f -exec chmod 644 {} +

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
