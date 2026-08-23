#!/usr/bin/env bash
# Removes what install-linux.sh put in place. Converted images are left alone.
set -u
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/jipeg"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
LABEL="Convert to JPEG (Jipeg)"
say() { printf '  %s\n' "$*"; }

printf '\n  Jipeg for Linux\n\n'
rm -f "$HOME/.local/bin/jipeg"
rm -f "$DATA/nautilus/scripts/$LABEL"
rm -f "$DATA/kio/servicemenus/jipeg.desktop"
rm -rf "$APP_DIR"
say "Removed the command, the right-click entries and $APP_DIR"

UCA="$HOME/.config/Thunar/uca.xml"
if [ -f "$UCA" ] && grep -q 'jipeg.sh' "$UCA"; then
    say "Thunar's action is still there - remove it from Edit > Configure custom actions."
fi
printf '\n'
