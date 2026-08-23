#!/usr/bin/env bash
# Jipeg installer for Linux and macOS - EXPERIMENTAL, and untested by its author.
#
#   curl -fsSL https://raw.githubusercontent.com/da0t-exe/Jipeg/main/platform/install.sh | bash
#
# Fetches the converter and the right-click integration for whichever desktop is
# here, and installs both into your home folder. Nothing needs root and nothing
# is written outside $HOME.
#
#   --uninstall     take it all back out again
set -u

RAW="https://raw.githubusercontent.com/da0t-exe/Jipeg/main/platform"
say() { printf '  %s\n' "$*"; }
die() { printf '\n  %s\n\n' "$*" >&2; exit 1; }

MODE="install"
for arg in "$@"; do
    case "$arg" in
        --uninstall) MODE="uninstall" ;;
        *) die "unknown option: $arg" ;;
    esac
done

case "$(uname -s)" in
    Linux)  OS="linux" ;;
    Darwin) OS="macos" ;;
    *)      die "Jipeg has nothing for $(uname -s). Windows, Linux and macOS only." ;;
esac

printf '\n  Jipeg  (experimental on %s)\n\n' "$OS"

# curl or wget, whichever is here.
fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
    else die "Neither curl nor wget is installed."; fi
}

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t jipeg)
trap 'rm -rf "$WORK"' EXIT

for f in jipeg.sh "$MODE-$OS.sh"; do
    say "Fetching $f"
    fetch "$RAW/$f" "$WORK/$f" || die "Could not download $f from GitHub."
    [ -s "$WORK/$f" ] || die "$f came back empty."
done

# The scripts are piped in from the network, so the shebang is checked rather
# than assumed: a proxy handing back an HTML error page would otherwise be run.
head -1 "$WORK/jipeg.sh" | grep -q '^#!' || die "That did not look like a script. Check your connection."

chmod +x "$WORK"/*.sh
printf '\n'
"$WORK/$MODE-$OS.sh"
