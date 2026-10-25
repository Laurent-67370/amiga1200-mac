#!/usr/bin/env bash
# Cœur Amiberry (base WinUAE 6) pour Mac Apple Silicon, avec le JIT ARM64, et son frontal : native/out/libcore.a
#
#   native/build-core.sh          (sur un Mac Apple Silicon, outils en ligne de commande de Xcode installés)
#
# Les sources d'Amiberry sont clonées dans native/src (même version que la version web et que la version Android),
# adaptées par native/patches/*.patch (touches, manette CD32, mémoire RTG des sauvegardes d'état, le frontal cadence
# les images), puis compilées par le Makefile libretro d'Amiberry (platform=osx : JIT ARM64 sur arm64).
# Le frontal est celui de la version web (amiga1200/wasm/frontend.c, sous-module), compilé tel quel : native/compat
# remplace les quelques fonctions d'Emscripten qu'il appelle. native/bridge.c le relie à l'application Swift.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
WEB="$ROOT/amiga1200"
AMB_REPO=https://github.com/BlitterStudio/amiberry.git
AMB_REV=ca2332df8cf914ec97c4a7c6ace38adcb3543b25   # Amiberry 8.3, comme amiga1200/wasm-amiberry/build.sh
SRC="$HERE/src"
OUT="$HERE/out"
JOBS=${JOBS:-$(sysctl -n hw.ncpu)}
[ "$(uname -m)" = arm64 ] || { echo "Mac Apple Silicon (arm64) nécessaire : le JIT ARM64 en dépend" >&2; exit 1; }
[ -f "$WEB/wasm/frontend.c" ] || { echo "sous-module amiga1200 absent : git submodule update --init" >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=13.0

if [ ! -d "$SRC/.git" ]; then
  git clone --filter=blob:none "$AMB_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin "$AMB_REV" 2>/dev/null || true
git -C "$SRC" checkout -q -f "$AMB_REV"
git -C "$SRC" clean -fdq -e '*.o' -e .patches.sum -e deps
git -C "$SRC" submodule update --init libretro/libco libretro/libretro-common
for p in "$HERE"/patches/*.patch; do git -C "$SRC" apply "$p"; done
# Fonctions C++ d'Amiberry appelées par le frontal (lecteurs de disquettes…) : compilées avec le cœur, mêmes options
cp "$WEB/wasm-amiberry/amb_glue.cpp" "$SRC/libretro/amb_glue.cpp"
sed -i '' 's|^SOURCES_CXX := \(.*\)$(SOURCES_MISC)$|SOURCES_CXX := \1$(SOURCES_MISC) $(LIBRETRO_DIR)/amb_glue.cpp|' "$SRC/libretro/Makefile"
grep -q 'amb_glue.cpp' "$SRC/libretro/Makefile" || { echo "Makefile d'Amiberry : liste des sources introuvable" >&2; exit 1; }
# Le Makefile ne suit pas les en-têtes : si les correctifs ont changé, les objets d'une compilation précédente sont jetés
PATCH_SUM=$(cat "$HERE"/patches/*.patch "$WEB/wasm-amiberry/amb_glue.cpp" | shasum -a 256 | cut -c1-16)
if [ "$(cat "$SRC/.patches.sum" 2>/dev/null)" != "$PATCH_SUM" ]; then
  find "$SRC" -name '*.o' -delete
  echo "$PATCH_SUM" > "$SRC/.patches.sum"
fi

mkdir -p "$OUT"
# zlib du système ; native/compat (faux en-têtes Emscripten pour amb_glue.cpp) passe par ZLIB_CFLAGS, ajouté aux chemins d'en-têtes
(cd "$SRC/libretro" && make -j"$JOBS" platform=osx ARCH=arm64 ZLIB_CFLAGS="-I$HERE/compat" ZLIB_LIBS=-lz >"$OUT/make.log" 2>&1) \
  || { tail -80 "$OUT/make.log"; exit 1; }
find "$SRC/src/jit" -name 'compemu_support*.o' | grep -q . || { echo "JIT absent de la compilation" >&2; exit 1; }

# Le cœur n'exporte que l'API libretro : on garde ses objets, réunis avec le frontal et le pont en une bibliothèque
cd "$OUT"
FLAGS=(-O3 -DFE_AMIBERRY -I"$HERE/compat" -I"$SRC/libretro" -I"$SRC/libretro/libretro-common/include")
# Le pont intercepte retro_set_environment (journal du cœur) : le frontal appelle notre fonction à sa place
clang "${FLAGS[@]}" -Dretro_set_environment=amb_frontend_set_environment -c "$WEB/wasm/frontend.c" -o frontend.o
clang "${FLAGS[@]}" -Wall -c "$HERE/bridge.c" -o bridge.o
# Copie de fichiers sur un disque dur (module commun aux applications Android, Mac et PC)
clang -O2 -Wall -c "$HERE/hdtools.c" -o hdtools.o
find "$SRC/src" "$SRC/libretro" "$SRC/external" -name '*.o' | sort >objs.txt
[ "$(wc -l <objs.txt)" -ge 300 ] || { echo "compilation incomplète, voir $OUT/make.log" >&2; exit 1; }
echo frontend.o >>objs.txt; echo bridge.o >>objs.txt; echo hdtools.o >>objs.txt
rm -f libcore.a
libtool -static -o libcore.a -filelist objs.txt 2>libtool.log || { cat libtool.log; exit 1; }

# Ressources : ROM AROS libres (démarrage sans Kickstart), WHDLoad d'Amiberry, bruits des lecteurs
RES="$OUT/resources"
rm -rf "$RES"; mkdir -p "$RES/aros"
cp "$WEB/vendor/aros/aros-20260820-rom.bin" "$RES/aros/aros-rom.bin"
cp "$WEB/vendor/aros/aros-20260820-ext.bin" "$RES/aros/aros-ext.bin"
cp -R "$SRC/whdboot" "$RES/whdboot"
cp -R "$SRC/data/floppy_sounds" "$RES/floppy_sounds"
echo "OK : $OUT/libcore.a ($(stat -f %z libcore.a) octets)"
