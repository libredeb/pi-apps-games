#!/bin/bash
set -euo pipefail

# Load extra utils functions
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CURRENT_DIR/../../utils/get-arch.sh"

# Compose package name
TARGET_ARCH=$(get_debian_arch)
GAME="quake3"

sudo apt install -y cmake build-essential zip python3 libsdl2-dev libgles2-mesa-dev libgl1-mesa-dev libopenal-dev libcurl4-openssl-dev || exit 1

rm -rf ioq3
git clone https://github.com/ioquake/ioq3.git || error "Could Not Pull Latest Source Code"
cd ioq3
#ENGINE_VERSION=$(sed -n 's/.*PROJECT_VERSION[[:space:]]*\([0-9.]*\).*/\1/p' cmake/identity.cmake)
VERSION="1.11.6"

# 1. Cambiamos el '#ifdef' por un nombre falso para deshabilitar por completo el primer bloque 'then'
sed -i 's/#ifdef STANDALONE/#ifdef FORZAR_MODO_DEMO_DESACTIVADO/g' code/qcommon/q_shared.h

# 2. Modificamos directamente las variables del bloque '#else' (que ahora se ejecutará siempre)
sed -i 's/"ioq3"/"ioquake3-demo"/g' code/qcommon/q_shared.h
sed -i 's/"baseq3"/"demoq3"/g' code/qcommon/q_shared.h
sed -i 's/"ioquake3"/"Quake III Arena Demo"/g' code/qcommon/q_shared.h
sed -i 's/"Quake3Arena"/"Quake3ArenaDemo"/g' code/qcommon/q_shared.h
sed -i 's/"Quake3"/"Quake3Demo"/g' code/qcommon/q_shared.h
sed -i 's/".q3a"/".q3a-demo"/g' code/qcommon/q_shared.h

# Q3 UI ignores PAD0_* keys; map them to arrows/enter/escape while menus are open.
python3 "$CURRENT_DIR/pkg/patch-gamepad-menu.py" code/client/cl_keys.c

cmake -S . -B build -DBUILD_SERVER=OFF -DBUILD_STANDALONE=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build

# Compose the DEB package
cd ..
PACKAGE_NAME="${GAME}-${VERSION}_${TARGET_ARCH}"
mkdir -p $PACKAGE_NAME/DEBIAN
mkdir -p $PACKAGE_NAME/usr/bin
mkdir -p $PACKAGE_NAME/usr/share/quake3
mkdir -p $PACKAGE_NAME/usr/share/quake3/demoq3
mkdir -p $PACKAGE_NAME/usr/share/applications
mkdir -p $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/

# Debian Control files
cp -R pkg/DEBIAN $PACKAGE_NAME/

# Binary file
cp -R ioq3/build/Release/* $PACKAGE_NAME/usr/share/quake3/

# Demo data files
curl -L -o /tmp/quake3-data.gz.sh "https://web.archive.org/web/20071229203613/ftp://ftp.idsoftware.com/idstuff/quake3/linux/linuxq3ademo-1.11-6.x86.gz.sh"
mkdir -p /tmp/demo_files
sed '1,/^END_OF_STUB$/d' /tmp/quake3-data.gz.sh | tar -xvz -C /tmp/demo_files
cp /tmp/demo_files/demoq3/pak0.pk3 $PACKAGE_NAME/usr/share/quake3/demoq3/pak0.pk3

# CMake instala cgame/ui/qagame en baseq3/, pero el motor parcheado usa demoq3/.
# Sin esos módulos se carga el ui.qvm de 1999 (API 3) y el motor espera API 6.
if [ ! -d "$PACKAGE_NAME/usr/share/quake3/baseq3" ]; then
    echo "error: no se generaron los módulos de juego en baseq3/" >&2
    exit 1
fi
cp -a "$PACKAGE_NAME/usr/share/quake3/baseq3/." "$PACKAGE_NAME/usr/share/quake3/demoq3/"
rm -rf "$PACKAGE_NAME/usr/share/quake3/baseq3"

if [ ! -d "$PACKAGE_NAME/usr/share/quake3/demoq3/vm" ]; then
    echo "error: faltan los QVM de ioquake3 en demoq3/vm/" >&2
    exit 1
fi
# pk3 posterior a pak0.pk3 para que pisen los QVM del demo
(cd "$PACKAGE_NAME/usr/share/quake3/demoq3" && zip -r zz-ioq3-vm.pk3 vm)

# Loose autoexec.cfg (ioquake3 refuses to exec it from a pk3)
cp "$CURRENT_DIR/pkg/autoexec.cfg" "$PACKAGE_NAME/usr/share/quake3/demoq3/autoexec.cfg"

# Custom executable
cat << 'EOF' > "$PACKAGE_NAME/usr/bin/quake3"
#!/bin/sh
export SDL_GAMECONTROLLERCONFIG="03000000412300003680000001010000,Arduino Leonardo,a:b0,b:b1,x:b3,y:b4,back:b10,start:b11,leftshoulder:b7,rightshoulder:b6,dpup:-a1,dpdown:+a1,dpleft:-a0,dpright:+a0,platform:Linux,"
export SDL_VIDEODRIVER=wayland
exec /usr/share/quake3/ioquake3 \
    +set fs_basepath /usr/share/quake3 \
    +set com_homepath .q3a \
    +set cl_renderer opengl1 \
    +set r_mode -1 \
    +set r_customwidth 720 \
    +set r_customheight 720 \
    +set r_fullscreen 1 \
    +set in_joystick 1 \
    +set vm_game 0 \
    +set vm_cgame 0 \
    +set vm_ui 0 \
    "$@"
EOF
chmod +x "$PACKAGE_NAME/usr/bin/quake3"

# Desktop and Icon
sudo tee $PACKAGE_NAME/usr/share/applications/quake3.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Quake 3
Comment=Fast-paced multiplayer first-person shooter
Exec=/usr/bin/quake3
Icon=quake3
Terminal=false
Categories=Game;ActionGame;
Keywords=quake;idsoftware;fps;shooter;retro;
EOF
cp pkg/icon.png $PACKAGE_NAME/usr/share/icons/hicolor/scalable/apps/quake3.png

sudo rm -rf ioq3 /tmp/quake3-data.gz.sh /tmp/demo_files

# Package DEB file
chmod 755 $PACKAGE_NAME/DEBIAN/postinst
chmod 755 $PACKAGE_NAME/DEBIAN/postrm
sudo chown -R root:root $PACKAGE_NAME
dpkg-deb --build $PACKAGE_NAME
sudo rm -rf $PACKAGE_NAME
