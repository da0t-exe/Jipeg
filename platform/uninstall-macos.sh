#!/usr/bin/env bash
# Removes what install-macos.sh put in place. Converted images are left alone.
set -u
printf '\n  Jipeg for macOS\n\n'
rm -rf "$HOME/Library/Services/Jipeg.workflow"
rm -rf "$HOME/Library/Application Support/Jipeg"
rm -f "$HOME/.local/bin/jipeg"
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
printf '  Removed the Quick Action and the command.\n'
printf '  The log is still in ~/Library/Logs/Jipeg if you want it.\n\n'
