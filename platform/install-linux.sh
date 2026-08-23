#!/usr/bin/env bash
# Installs Jipeg's right-click entry on Linux - EXPERIMENTAL, untested.
#
# Nothing is installed system-wide and nothing needs root. Three file managers
# are covered because they each invented their own way of doing this: GNOME
# Files reads executable scripts from a folder, KDE reads .desktop files, and
# Thunar keeps its actions in one XML file of its own.
set -u

BIN_DIR="$HOME/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/jipeg"
SRC="$(cd "$(dirname "$0")" && pwd)/jipeg.sh"
LABEL="Convert to JPEG (Jipeg)"

say() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

printf '\n  Jipeg for Linux  (experimental)\n\n'

[ -f "$SRC" ] || { say "jipeg.sh is missing next to this script."; exit 1; }

mkdir -p "$APP_DIR" "$BIN_DIR"
install -m 755 "$SRC" "$APP_DIR/jipeg.sh"
ln -sf "$APP_DIR/jipeg.sh" "$BIN_DIR/jipeg"
say "Installed  $APP_DIR/jipeg.sh"
say "Command    jipeg  (in $BIN_DIR)"

# --- what it needs -----------------------------------------------------------
MISSING=""
have cjpegli || MISSING="$MISSING cjpegli"
have oxipng  || MISSING="$MISSING oxipng"
have dwebp   || MISSING="$MISSING dwebp"
if [ -n "$MISSING" ]; then
    printf '\n'
    say "Missing:$MISSING"
    say "  Debian/Ubuntu   sudo apt install libjxl-tools oxipng webp"
    say "  Fedora          sudo dnf install libjxl-utils oxipng libwebp-tools"
    say "  Arch            sudo pacman -S libjxl oxipng libwebp"
    say "cjpegli is the only one it cannot work without."
fi

INSTALLED=""

# --- GNOME Files (Nautilus) --------------------------------------------------
NAUT="${XDG_DATA_HOME:-$HOME/.local/share}/nautilus/scripts"
if [ -d "$HOME/.local/share/nautilus" ] || have nautilus; then
    mkdir -p "$NAUT"
    cat > "$NAUT/$LABEL" <<SCRIPT
#!/usr/bin/env bash
# Nautilus hands the selection over on standard input, one path per line.
IFS=\$'\n' read -r -d '' -a picked < <(printf '%s\0' "\$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS")
exec "$APP_DIR/jipeg.sh" "\${picked[@]}"
SCRIPT
    chmod +x "$NAUT/$LABEL"
    INSTALLED="$INSTALLED GNOME-Files"
fi

# --- KDE (Dolphin) -----------------------------------------------------------
KDE="${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus"
if have dolphin || [ -d "$HOME/.local/share/kio" ]; then
    mkdir -p "$KDE"
    cat > "$KDE/jipeg.desktop" <<DESKTOP
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=image/png;image/jpeg;image/gif;image/bmp;image/tiff;image/webp;
Actions=jipegConvert;
X-KDE-Priority=TopLevel

[Desktop Action jipegConvert]
Name=$LABEL
Icon=image-x-generic
Exec=$APP_DIR/jipeg.sh %F
DESKTOP
    chmod +x "$KDE/jipeg.desktop"
    INSTALLED="$INSTALLED KDE-Dolphin"
fi

# --- XFCE (Thunar) -----------------------------------------------------------
# Thunar keeps every custom action in one file of its own. It is only written
# here when there is nothing to overwrite, because merging into somebody's
# existing actions blind is a good way to lose them.
UCA="$HOME/.config/Thunar/uca.xml"
if have thunar; then
    if [ ! -f "$UCA" ]; then
        mkdir -p "$(dirname "$UCA")"
        cat > "$UCA" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<actions>
<action>
    <icon>image-x-generic</icon>
    <name>$LABEL</name>
    <command>$APP_DIR/jipeg.sh %F</command>
    <description>Make the picture lighter</description>
    <patterns>*.png;*.jpg;*.jpeg;*.gif;*.bmp;*.tif;*.tiff;*.webp</patterns>
    <image-files/>
</action>
</actions>
XML
        INSTALLED="$INSTALLED XFCE-Thunar"
    else
        printf '\n'
        say "Thunar already has custom actions, so its file was left alone."
        say "Add one by hand: Edit > Configure custom actions, command:"
        say "  $APP_DIR/jipeg.sh %F"
    fi
fi

printf '\n'
if [ -n "$INSTALLED" ]; then
    say "Right-click entry added for:$INSTALLED"
    say "Log out and back in, or restart the file manager, for it to appear."
else
    say "No supported file manager was found."
    say "The jipeg command works either way."
fi
printf '\n'
