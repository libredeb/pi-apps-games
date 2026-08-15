#!/bin/bash
# build-freesound-audio.sh
#
# Build audio/default.zip for ClassiCube using ONLY redistributable Freesound
# samples. Minecraft / Mojang / C418 packaged audio is never downloaded.
#
# Sources:
#   grass / glass / gravel — ClassiCube/doc/sound-credits.md
#   wood / stone           — Freesound recordings C418 downloaded for Classic
#                            (credited on minecraft.net / MobyGames). These are
#                            the original CC BY files, NOT the processed WAVs
#                            from resources.download.minecraft.net.
#   sand / snow / cloth    — CC0 Freesound replacements. Classic had no public
#                            Freesound mapping for these (snow was recorded by
#                            C418; sand/cloth were never identified).
#
# Output WAV names match what ClassiCube loads from audio/default.zip
# (see src/Audio.c: dig_<material><n>.wav and step_<material><n>.wav).
#
# Requirements: wget, ffmpeg (or sox), zip
# Usage: ./build-freesound-audio.sh [output_directory]
#
# If any Freesound page or preview download fails, this script prints an
# error and exits non-zero so the .deb build aborts.

set -euo pipefail

OUT_DIR="${1:-./audio}"
WGET_UA="Mozilla/5.0 (compatible; ClassicCube-deb-packaging/1.0)"
TMP_DIR=$(mktemp -d)
CREDITS_FILE=""
RAW_CACHE=""

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
CREDITS_FILE="$OUT_DIR/SOUNDS-CREDITS.txt"
WAV_DIR="$TMP_DIR/wavs"
RAW_CACHE="$TMP_DIR/rawcache"
mkdir -p "$WAV_DIR" "$RAW_CACHE"

# Do not leave a half-written zip behind if a later step fails.
rm -f "$OUT_DIR/default.zip"

if ! command -v wget >/dev/null 2>&1; then
    echo "ERROR: wget is required to download Freesound samples." >&2
    exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
    echo "ERROR: zip is required to create audio/default.zip." >&2
    exit 1
fi

CONVERT=""
if command -v ffmpeg >/dev/null 2>&1; then
    CONVERT="ffmpeg"
elif command -v sox >/dev/null 2>&1; then
    CONVERT="sox"
else
    echo "ERROR: ffmpeg or sox is required to convert Freesound previews to 16-bit PCM WAV." >&2
    echo "ClassiCube rejects non-16-bit WAV files (see src/Audio.c)." >&2
    exit 1
fi

echo "==> Building ClassiCube audio/default.zip from redistributable Freesound samples..."
echo "    Converter: $CONVERT"

# ---------------------------------------------------------------------------
# Format: filename|freesound_page_url|author|fallback_hq_preview_url|start_sec|duration_sec
#
# start_sec / duration_sec are optional. When set, a short clip is cut from a
# longer recording (walking loops, cloth foley, long stone impacts). Empty
# fields mean "convert the whole preview".
#
# Preview CDN filenames change over time, so the script scrapes the current
# -hq.mp3 (then -lq.mp3) from the Freesound page before using the fallback.
# ---------------------------------------------------------------------------

declare -a SOUNDS=(
    # --- Grass (Snoman) — CC BY 4.0 — ClassiCube sound-credits.md ---
    "dig_grass1.wav|https://freesound.org/people/Snoman/sounds/9904/|Snoman|https://cdn.freesound.org/previews/9/9904_29481-hq.mp3||"
    "dig_grass2.wav|https://freesound.org/people/Snoman/sounds/9905/|Snoman|https://cdn.freesound.org/previews/9/9905_29481-hq.mp3||"
    "dig_grass3.wav|https://freesound.org/people/Snoman/sounds/9906/|Snoman|https://cdn.freesound.org/previews/9/9906_29481-hq.mp3||"
    "dig_grass4.wav|https://freesound.org/people/Snoman/sounds/9907/|Snoman|https://cdn.freesound.org/previews/9/9907_29481-hq.mp3||"

    # --- Glass — ClassiCube sound-credits.md ---
    "dig_glass1.wav|https://freesound.org/people/datasoundsample/sounds/41348/|datasoundsample|https://cdn.freesound.org/previews/41/41348_433684-hq.mp3||"
    "dig_glass2.wav|https://freesound.org/people/lsprice/sounds/88808/|lsprice|https://cdn.freesound.org/previews/88/88808_193132-hq.mp3||"
    "dig_glass3.wav|https://freesound.org/people/cmusounddesign/sounds/71947/|cmusounddesign|https://cdn.freesound.org/previews/71/71947_1059930-hq.mp3||"

    # --- Gravel (tigersound) — CC BY-NC 4.0 — ClassiCube sound-credits.md ---
    # Same walking loop; four short slices instead of shipping the 24s file.
    "dig_gravel1.wav|https://freesound.org/people/tigersound/sounds/15562/|tigersound|https://cdn.freesound.org/previews/15/15562_23035-hq.mp3|0.2|0.40"
    "dig_gravel2.wav|https://freesound.org/people/tigersound/sounds/15562/|tigersound|https://cdn.freesound.org/previews/15/15562_23035-hq.mp3|1.4|0.40"
    "dig_gravel3.wav|https://freesound.org/people/tigersound/sounds/15562/|tigersound|https://cdn.freesound.org/previews/15/15562_23035-hq.mp3|2.6|0.40"
    "dig_gravel4.wav|https://freesound.org/people/tigersound/sounds/15562/|tigersound|https://cdn.freesound.org/previews/15/15562_23035-hq.mp3|3.8|0.40"

    # --- Wood (schluppipuppie) — CC BY 4.0 ---
    # holz-holz-01.wav is credited in Minecraft's Freesound list. Variants 02/03
    # and messer-holz-02 are from the same kitchen-wood session.
    "dig_wood1.wav|https://freesound.org/people/schluppipuppie/sounds/12835/|schluppipuppie|https://cdn.freesound.org/previews/12/12835_4942-hq.mp3||"
    "dig_wood2.wav|https://freesound.org/people/schluppipuppie/sounds/12836/|schluppipuppie|https://cdn.freesound.org/previews/12/12836_4942-hq.mp3||"
    "dig_wood3.wav|https://freesound.org/people/schluppipuppie/sounds/12837/|schluppipuppie|https://cdn.freesound.org/previews/12/12837_4942-hq.mp3||"
    "dig_wood4.wav|https://freesound.org/people/schluppipuppie/sounds/12850/|schluppipuppie|https://cdn.freesound.org/previews/12/12850_4942-hq.mp3||"

    # --- Stone (thanvannispen) — CC BY 4.0 ---
    # stone_on_stone_impact_loud4 and the dragging take were credited in
    # Minecraft. loud1–loud4 are the matching impact set; trimmed to a hit.
    "dig_stone1.wav|https://freesound.org/people/thanvannispen/sounds/30008/|thanvannispen|https://cdn.freesound.org/previews/30/30008_13258-hq.mp3|0|0.45"
    "dig_stone2.wav|https://freesound.org/people/thanvannispen/sounds/30009/|thanvannispen|https://cdn.freesound.org/previews/30/30009_13258-hq.mp3|0|0.45"
    "dig_stone3.wav|https://freesound.org/people/thanvannispen/sounds/30010/|thanvannispen|https://cdn.freesound.org/previews/30/30010_13258-hq.mp3|0|0.45"
    "dig_stone4.wav|https://freesound.org/people/thanvannispen/sounds/30011/|thanvannispen|https://cdn.freesound.org/previews/30/30011_13258-hq.mp3|0|0.45"

    # --- Sand (BlondPanda) — CC0 ---
    # Short fine-sand/snow steps. Used for sand (snow has its own crunchy source).
    "dig_sand1.wav|https://freesound.org/people/BlondPanda/sounds/778520/|BlondPanda|https://cdn.freesound.org/previews/778/778520_8927049-hq.mp3||"
    "dig_sand2.wav|https://freesound.org/people/BlondPanda/sounds/778521/|BlondPanda|https://cdn.freesound.org/previews/778/778521_8927049-hq.mp3||"
    "dig_sand3.wav|https://freesound.org/people/BlondPanda/sounds/778522/|BlondPanda|https://cdn.freesound.org/previews/778/778522_8927049-hq.mp3||"
    "dig_sand4.wav|https://freesound.org/people/BlondPanda/sounds/778523/|BlondPanda|https://cdn.freesound.org/previews/778/778523_8927049-hq.mp3||"

    # --- Snow (lwdickens) — CC0 ---
    # Classic snow was a C418 original, not a documented Freesound file.
    "dig_snow1.wav|https://freesound.org/people/lwdickens/sounds/261224/|lwdickens|https://cdn.freesound.org/previews/261/261224_2663250-hq.mp3|2.0|0.40"
    "dig_snow2.wav|https://freesound.org/people/lwdickens/sounds/261224/|lwdickens|https://cdn.freesound.org/previews/261/261224_2663250-hq.mp3|10.0|0.40"
    "dig_snow3.wav|https://freesound.org/people/lwdickens/sounds/261224/|lwdickens|https://cdn.freesound.org/previews/261/261224_2663250-hq.mp3|20.0|0.40"
    "dig_snow4.wav|https://freesound.org/people/lwdickens/sounds/261224/|lwdickens|https://cdn.freesound.org/previews/261/261224_2663250-hq.mp3|30.0|0.40"

    # --- Cloth (xkeril) — CC0 ---
    # Classic cloth/wool had no documented Freesound mapping.
    "dig_cloth1.wav|https://freesound.org/people/xkeril/sounds/788342/|xkeril|https://cdn.freesound.org/previews/788/788342_13504080-hq.mp3|2.0|0.35"
    "dig_cloth2.wav|https://freesound.org/people/xkeril/sounds/788342/|xkeril|https://cdn.freesound.org/previews/788/788342_13504080-hq.mp3|12.0|0.35"
    "dig_cloth3.wav|https://freesound.org/people/xkeril/sounds/788342/|xkeril|https://cdn.freesound.org/previews/788/788342_13504080-hq.mp3|22.0|0.35"
    "dig_cloth4.wav|https://freesound.org/people/xkeril/sounds/788342/|xkeril|https://cdn.freesound.org/previews/788/788342_13504080-hq.mp3|32.0|0.35"
)

abort_download() {
    local what="$1"
    echo "ERROR: Failed to obtain Freesound audio for $what" >&2
    echo "       The package build cannot continue without redistributable sounds." >&2
    echo "       Check the Freesound page, then re-run the build." >&2
    exit 1
}

is_audio_file() {
    local path="$1"
    local desc
    [[ -s "$path" ]] || return 1
    if command -v file >/dev/null 2>&1; then
        desc="$(file -b "$path" || true)"
        printf '%s\n' "$desc" | grep -qiE 'audio|mpeg|mp3|ogg|vorbis|wav|riff|media'
    else
        return 0
    fi
}

scrape_preview_urls() {
    local page_url="$1"
    local html hq lq
    html=$(wget -q -U "$WGET_UA" -O - "$page_url") || return 1
    hq=$(printf '%s\n' "$html" | grep -oE 'https://cdn\.freesound\.org/previews/[0-9]+/[0-9]+_[0-9]+-hq\.mp3' | head -n1 || true)
    lq=$(printf '%s\n' "$html" | grep -oE 'https://cdn\.freesound\.org/previews/[0-9]+/[0-9]+_[0-9]+-lq\.mp3' | head -n1 || true)
    [[ -n "$hq" ]] && printf '%s\n' "$hq"
    [[ -n "$lq" ]] && printf '%s\n' "$lq"
    return 0
}

download_preview() {
    local dest="$1"
    local url="$2"
    rm -f "$dest"
    if ! wget -q --show-progress -U "$WGET_UA" -O "$dest" "$url"; then
        rm -f "$dest"
        return 1
    fi
    if ! is_audio_file "$dest"; then
        rm -f "$dest"
        return 1
    fi
    return 0
}

page_cache_path() {
    local page_url="$1"
    local key
    key=$(printf '%s' "$page_url" | sha256sum | awk '{print $1}')
    printf '%s/%s' "$RAW_CACHE" "$key"
}

convert_to_wav() {
    local src="$1"
    local dest="$2"
    local ss="${3:-}"
    local dur="${4:-}"

    if [[ "$CONVERT" == "ffmpeg" ]]; then
        local cmd=(ffmpeg -y -i "$src")
        [[ -n "$ss" ]] && cmd+=(-ss "$ss")
        [[ -n "$dur" ]] && cmd+=(-t "$dur")
        cmd+=(-acodec pcm_s16le -ar 44100 -ac 1 "$dest")
        "${cmd[@]}" >/dev/null 2>&1
    else
        if [[ -n "$ss" || -n "$dur" ]]; then
            sox "$src" -r 44100 -c 1 -b 16 "$dest" trim "${ss:-0}" ${dur:+"$dur"}
        else
            sox "$src" -r 44100 -c 1 -b 16 "$dest"
        fi
    fi
}

download_and_convert() {
    local dest_name="$1"
    local page_url="$2"
    local author="$3"
    local fallback_url="$4"
    local ss="${5:-}"
    local dur="${6:-}"
    local tmp_in tmp_out url scraped
    local u ok

    echo "  -> $dest_name  ($author)"
    echo "     page: $page_url"
    [[ -n "$ss$dur" ]] && echo "     clip: start=${ss:-0}s duration=${dur:-full}s"

    tmp_in="$(page_cache_path "$page_url")"
    tmp_out="$WAV_DIR/$dest_name"

    if [[ ! -s "$tmp_in" ]]; then
        mapfile -t scraped < <(scrape_preview_urls "$page_url" || true)

        declare -a candidates=()
        for u in "${scraped[@]+"${scraped[@]}"}"; do
            [[ -n "$u" ]] && candidates+=("$u")
        done
        candidates+=("$fallback_url")

        ok=0
        for url in "${candidates[@]}"; do
            echo "     trying: $url"
            if download_preview "$tmp_in" "$url"; then
                ok=1
                break
            fi
        done
        if [[ "$ok" -ne 1 ]]; then
            abort_download "$dest_name ($page_url)"
        fi
    else
        echo "     using cached download for this Freesound page"
    fi

    if ! convert_to_wav "$tmp_in" "$tmp_out" "$ss" "$dur"; then
        echo "ERROR: Failed to convert $dest_name to 16-bit 44100 Hz mono WAV." >&2
        exit 1
    fi
    if [[ ! -s "$tmp_out" ]]; then
        echo "ERROR: Converter produced an empty file for $dest_name." >&2
        exit 1
    fi
}

for entry in "${SOUNDS[@]}"; do
    IFS='|' read -r name page author fallback ss dur <<< "$entry"
    download_and_convert "$name" "$page" "$author" "$fallback" "$ss" "$dur"
done

# ClassiCube loads both dig_* and step_* boards from the same zip.
echo "==> Generating step_*.wav from dig_*.wav..."
for f in "$WAV_DIR"/dig_*.wav; do
    [[ -f "$f" ]] || continue
    base="$(basename "$f")"
    cp "$f" "$WAV_DIR/${base/dig_/step_}"
done

required_wavs=(
    dig_grass1.wav dig_grass2.wav dig_grass3.wav dig_grass4.wav
    step_grass1.wav step_grass2.wav step_grass3.wav step_grass4.wav
    dig_glass1.wav dig_glass2.wav dig_glass3.wav
    step_glass1.wav step_glass2.wav step_glass3.wav
    dig_gravel1.wav dig_gravel2.wav dig_gravel3.wav dig_gravel4.wav
    step_gravel1.wav step_gravel2.wav step_gravel3.wav step_gravel4.wav
    dig_wood1.wav dig_wood2.wav dig_wood3.wav dig_wood4.wav
    step_wood1.wav step_wood2.wav step_wood3.wav step_wood4.wav
    dig_stone1.wav dig_stone2.wav dig_stone3.wav dig_stone4.wav
    step_stone1.wav step_stone2.wav step_stone3.wav step_stone4.wav
    dig_sand1.wav dig_sand2.wav dig_sand3.wav dig_sand4.wav
    step_sand1.wav step_sand2.wav step_sand3.wav step_sand4.wav
    dig_snow1.wav dig_snow2.wav dig_snow3.wav dig_snow4.wav
    step_snow1.wav step_snow2.wav step_snow3.wav step_snow4.wav
    dig_cloth1.wav dig_cloth2.wav dig_cloth3.wav dig_cloth4.wav
    step_cloth1.wav step_cloth2.wav step_cloth3.wav step_cloth4.wav
)
for wav in "${required_wavs[@]}"; do
    if [[ ! -s "$WAV_DIR/$wav" ]]; then
        echo "ERROR: Missing required WAV that ClassiCube expects: $wav" >&2
        exit 1
    fi
done

echo "==> Creating $OUT_DIR/default.zip..."
(
    cd "$WAV_DIR"
    zip -q -9 "$OUT_DIR/default.zip" "${required_wavs[@]}"
)

cat > "$CREDITS_FILE" << 'EOF'
Sound Credits
=======================================

The sound effects in this package come from Freesound.org.
Minecraft / Mojang / C418 packaged music and sounds are NOT included
and must not be redistributed.

Official ClassiCube credits (grass / glass / gravel):
  https://github.com/ClassiCube/ClassiCube/blob/master/doc/sound-credits.md

Texture pack (also redistributable, not from Mojang):
  https://static.classicube.net/default.zip
  packaged as texpacks/classicube.zip

List of included sounds
---------------------------------------

dig/step_grass1-4
  - grass1.wav … grass4.wav by Snoman
  - License: CC BY 4.0
    https://creativecommons.org/licenses/by/4.0/
  - https://freesound.org/people/Snoman/sounds/9904/
  - https://freesound.org/people/Snoman/sounds/9905/
  - https://freesound.org/people/Snoman/sounds/9906/
  - https://freesound.org/people/Snoman/sounds/9907/

dig/step_glass1
  - glass shatter.wav by datasoundsample
  - License: CC BY 4.0
    https://creativecommons.org/licenses/by/4.0/
  - https://freesound.org/people/datasoundsample/sounds/41348/

dig/step_glass2
  - gb12.aif by lsprice
  - License: CC BY 3.0
    https://creativecommons.org/licenses/by/3.0/
  - https://freesound.org/people/lsprice/sounds/88808/

dig/step_glass3
  - bm_Glass_Break.wav by cmusounddesign
  - License: CC BY 4.0
    https://creativecommons.org/licenses/by/4.0/
  - https://freesound.org/people/cmusounddesign/sounds/71947/

dig/step_gravel1-4
  - gravel walking.aif by tigersound (four short slices of the same recording)
  - License: CC BY-NC 4.0 (non-commercial; attribution required)
    https://creativecommons.org/licenses/by-nc/4.0/
  - https://freesound.org/people/tigersound/sounds/15562/

dig/step_wood1-4
  - holz - holz - 01/02/03.wav and messer - holz - 02.wav by schluppipuppie
  - License: CC BY 4.0
    https://creativecommons.org/licenses/by/4.0/
  - Original Freesound recordings used in Classic (not Mojang's packaged WAVs)
  - https://freesound.org/people/schluppipuppie/sounds/12835/
  - https://freesound.org/people/schluppipuppie/sounds/12836/
  - https://freesound.org/people/schluppipuppie/sounds/12837/
  - https://freesound.org/people/schluppipuppie/sounds/12850/

dig/step_stone1-4
  - stone_on_stone_impact_loud1–4.aif by thanvannispen
  - License: CC BY 4.0
    https://creativecommons.org/licenses/by/4.0/
  - Original Freesound recordings used in Classic (not Mojang's packaged WAVs)
  - https://freesound.org/people/thanvannispen/sounds/30008/
  - https://freesound.org/people/thanvannispen/sounds/30009/
  - https://freesound.org/people/thanvannispen/sounds/30010/
  - https://freesound.org/people/thanvannispen/sounds/30011/

dig/step_sand1-4
  - Steps_Fine_Snow_Or_Sand_Gentle 01–04 by BlondPanda
  - License: CC0 1.0
    https://creativecommons.org/publicdomain/zero/1.0/
  - Replacement: Classic sand had no documented Freesound mapping
  - https://freesound.org/people/BlondPanda/sounds/778520/
  - https://freesound.org/people/BlondPanda/sounds/778521/
  - https://freesound.org/people/BlondPanda/sounds/778522/
  - https://freesound.org/people/BlondPanda/sounds/778523/

dig/step_snow1-4
  - footsteps crunchy snow 2 people.wav by lwdickens (four short slices)
  - License: CC0 1.0
    https://creativecommons.org/publicdomain/zero/1.0/
  - Replacement: Classic snow was recorded by C418, not a Freesound original
  - https://freesound.org/people/lwdickens/sounds/261224/

dig/step_cloth1-4
  - Clothes movements (walking foley) by xkeril (four short slices)
  - License: CC0 1.0
    https://creativecommons.org/publicdomain/zero/1.0/
  - Replacement: Classic cloth/wool had no documented Freesound mapping
  - https://freesound.org/people/xkeril/sounds/788342/

Notes
---------------------------------------
- Files were converted to 16-bit 44100 Hz mono WAV, the format ClassiCube
  accepts (see src/Audio.c).
- Filenames inside audio/default.zip are the names ClassiCube expects
  (dig_grass1.wav, step_grass1.wav, dig_wood1.wav, …).
- These are not bit-identical to Minecraft Classic: C418 cropped and
  processed some Freesound originals, and snow/sand/cloth are substitutes.
EOF

echo "==> Done."
echo "    Zip generated : $OUT_DIR/default.zip"
echo "    Credits       : $CREDITS_FILE"
