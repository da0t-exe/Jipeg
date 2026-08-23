#!/usr/bin/env bash
# Jipeg for Linux and macOS - EXPERIMENTAL, and not tested by its author.
#
# Same idea as the Windows version: hand it images, get lighter files back, and
# never a heavier one. It follows the same rules, with one honest gap noted
# below. Nothing is ever written over an original.
#
#   jipeg.sh FILE [FILE...]      convert those files
#   jipeg.sh DIRECTORY           convert the images directly inside it
#
# It needs cjpegli, and it will use oxipng and dwebp when they are there:
#   Debian/Ubuntu   sudo apt install libjxl-tools oxipng webp
#   Fedora          sudo dnf install libjxl-utils oxipng libwebp-tools
#   Arch            sudo pacman -S libjxl oxipng libwebp
#   macOS           brew install jpeg-xl oxipng webp
set -u

SUFFIX="_jipeg"
QUALITY="${JIPEG_QUALITY:-90}"

case "$(uname -s)" in
    Darwin) LOG_DIR="$HOME/Library/Logs/Jipeg" ;;
    *)      LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/jipeg" ;;
esac
LOG="$LOG_DIR/jipeg.log"

log() {
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null
    # kept from growing on a machine nobody is watching
    if [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 131072 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# One line, wherever this desktop puts them.
notify() {
    if have notify-send; then
        notify-send -a Jipeg "Jipeg" "$1" 2>/dev/null
    elif have osascript; then
        osascript -e "display notification \"$1\" with title \"Jipeg\"" 2>/dev/null
    fi
    printf '%s\n' "$1"
}

size_of() { wc -c < "$1" | tr -d ' '; }

# A free name next to the original, never over it.
free_path() {
    local dir="$1" base="$2" ext="$3" try="$1/$2$3" n=1
    while [ -e "$try" ]; do try="$dir/$base ($n)$ext"; n=$((n + 1)); done
    printf '%s' "$try"
}

# Colour type lives at byte 25 of a PNG: 4 and 6 carry an alpha channel, and a
# palette image (3) is transparent only if a tRNS chunk turns up before the
# pixel data.
png_has_alpha() {
    local t
    t=$(od -An -tu1 -j25 -N1 "$1" 2>/dev/null | tr -d ' ')
    [ "$t" = "4" ] || [ "$t" = "6" ] && return 0
    [ "$t" = "3" ] || return 1
    head -c 4096 "$1" 2>/dev/null | grep -aq 'tRNS'
}

# The Windows version measures the density of hard colour transitions to decide
# this, which needs a pixel scan. Here it leans on ImageMagick when it is
# installed and falls back to the safe answer when it is not: few colours means
# flat artwork or text, where 4:2:0 smears the edges.
chroma_for() {
    local f="$1" k
    case "${f##*.}" in
        jpg|jpeg|JPG|JPEG) printf '420'; return ;;
    esac
    if have identify; then
        k=$(identify -format '%k' "$f" 2>/dev/null | head -1)
        case "$k" in
            ''|*[!0-9]*) printf '444' ;;
            *) if [ "$k" -le 4096 ]; then printf '444'; else printf '420'; fi ;;
        esac
    else
        printf '444'
    fi
}

shrink_png() {   # src dst -> 0 if it came out smaller
    have oxipng || return 1
    cp -p "$1" "$2" || return 1
    oxipng -o 4 --strip safe -q "$2" >/dev/null 2>&1 || { rm -f "$2"; return 1; }
    [ "$(size_of "$2")" -lt "$(size_of "$1")" ] || { rm -f "$2"; return 1; }
    return 0
}

DONE=0; KEPT=0; FAILED=0; IN_TOTAL=0; OUT_TOTAL=0

convert_one() {
    local src="$1"
    local dir base ext lower tmp target insize outsize
    dir=$(dirname "$src"); base=$(basename "$src"); ext="${base##*.}"; base="${base%.*}"
    lower=$(printf '%s' "$ext" | tr 'A-Z' 'a-z')
    insize=$(size_of "$src")

    # A PNG with transparent pixels never becomes a JPEG: JPEG has no alpha, so
    # the only way to make one is to paint something behind the picture.
    if [ "$lower" = "png" ] && png_has_alpha "$src"; then
        tmp="$dir/.jipeg-$$-$RANDOM.png"
        if shrink_png "$src" "$tmp"; then
            target=$(free_path "$dir" "$base$SUFFIX" ".png")
            mv "$tmp" "$target"; touch -r "$src" "$target" 2>/dev/null
            outsize=$(size_of "$target")
            IN_TOTAL=$((IN_TOTAL + insize)); OUT_TOTAL=$((OUT_TOTAL + outsize)); DONE=$((DONE + 1))
        else
            KEPT=$((KEPT + 1)); log "kept     $base.$ext (already as small as it gets)"
        fi
        return
    fi

    have cjpegli || { FAILED=$((FAILED + 1)); log "failed   $base.$ext (cjpegli is not installed)"; return; }

    tmp="$dir/.jipeg-$$-$RANDOM.jpg"
    if ! cjpegli "$src" "$tmp" -q "$QUALITY" -p 1 \
                 --chroma_subsampling="$(chroma_for "$src")" >/dev/null 2>&1; then
        rm -f "$tmp"
        # A PNG the encoder refused, or one that would only get heavier, still
        # has the lossless route open to it.
        if [ "$lower" = "png" ]; then
            tmp="$dir/.jipeg-$$-$RANDOM.png"
            if shrink_png "$src" "$tmp"; then
                target=$(free_path "$dir" "$base$SUFFIX" ".png")
                mv "$tmp" "$target"; touch -r "$src" "$target" 2>/dev/null
                IN_TOTAL=$((IN_TOTAL + insize)); OUT_TOTAL=$((OUT_TOTAL + $(size_of "$target"))); DONE=$((DONE + 1))
                return
            fi
        fi
        FAILED=$((FAILED + 1)); log "failed   $base.$ext (the encoder refused it)"
        return
    fi

    outsize=$(size_of "$tmp")
    if [ "$outsize" -ge "$insize" ]; then
        rm -f "$tmp"
        if [ "$lower" = "png" ]; then
            tmp="$dir/.jipeg-$$-$RANDOM.png"
            if shrink_png "$src" "$tmp"; then
                target=$(free_path "$dir" "$base$SUFFIX" ".png")
                mv "$tmp" "$target"; touch -r "$src" "$target" 2>/dev/null
                IN_TOTAL=$((IN_TOTAL + insize)); OUT_TOTAL=$((OUT_TOTAL + $(size_of "$target"))); DONE=$((DONE + 1))
                return
            fi
        fi
        KEPT=$((KEPT + 1)); log "kept     $base.$ext (a JPEG would have been bigger)"
        return
    fi

    target=$(free_path "$dir" "$base$SUFFIX" ".jpg")
    mv "$tmp" "$target"; touch -r "$src" "$target" 2>/dev/null
    IN_TOTAL=$((IN_TOTAL + insize)); OUT_TOTAL=$((OUT_TOTAL + outsize)); DONE=$((DONE + 1))
}

[ $# -gt 0 ] || { printf 'usage: %s FILE [FILE...] | DIRECTORY\n' "$(basename "$0")" >&2; exit 2; }

log "context  $(uname -s) $(uname -r), quality $QUALITY, $# argument(s)"

for arg in "$@"; do
    if [ -d "$arg" ]; then
        for f in "$arg"/*; do
            [ -f "$f" ] || continue
            case "$(printf '%s' "${f##*.}" | tr 'A-Z' 'a-z')" in
                png|jpg|jpeg|jpe|gif|bmp|tif|tiff|webp|ppm|pnm|pgm|pam|pfm|jxl) ;;
                *) continue ;;
            esac
            case "$f" in *"$SUFFIX".*) continue ;; esac
            convert_one "$f"
        done
    elif [ -f "$arg" ]; then
        case "$arg" in *"$SUFFIX".*) continue ;; esac
        convert_one "$arg"
    fi
done

MSG="$DONE converted"
[ "$FAILED" -gt 0 ] && MSG="$MSG, $FAILED failed"
[ "$KEPT" -gt 0 ] && MSG="$MSG, $KEPT left alone"
if [ "$IN_TOTAL" -gt 0 ] && [ "$DONE" -gt 0 ]; then
    MSG="$MSG - $(( (IN_TOTAL - OUT_TOTAL) * 100 / IN_TOTAL ))% smaller"
fi
log "batch    $MSG"
notify "$MSG"
