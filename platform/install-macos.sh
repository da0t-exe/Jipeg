#!/usr/bin/env bash
# Installs Jipeg as a Finder Quick Action on macOS - EXPERIMENTAL, untested.
#
# A Quick Action is an Automator workflow bundle dropped into ~/Library/Services.
# Nothing needs root and nothing is written outside your home folder.
set -u

APP_DIR="$HOME/Library/Application Support/Jipeg"
SRV="$HOME/Library/Services/Jipeg.workflow"
SRC="$(cd "$(dirname "$0")" && pwd)/jipeg.sh"

say() { printf '  %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

printf '\n  Jipeg for macOS  (experimental)\n\n'

[ -f "$SRC" ] || { say "jipeg.sh is missing next to this script."; exit 1; }

mkdir -p "$APP_DIR" "$HOME/.local/bin"
install -m 755 "$SRC" "$APP_DIR/jipeg.sh"
ln -sf "$APP_DIR/jipeg.sh" "$HOME/.local/bin/jipeg"
say "Installed  $APP_DIR/jipeg.sh"

MISSING=""
have cjpegli || MISSING="$MISSING cjpegli"
have oxipng  || MISSING="$MISSING oxipng"
have dwebp   || MISSING="$MISSING dwebp"
if [ -n "$MISSING" ]; then
    printf '\n'
    say "Missing:$MISSING"
    say "  brew install jpeg-xl oxipng webp"
    say "cjpegli is the only one it cannot work without."
fi

rm -rf "$SRV"
mkdir -p "$SRV/Contents"

cat > "$SRV/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Convert to JPEG (Jipeg)</string>
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSRequiredContext</key>
            <dict>
                <key>NSApplicationIdentifier</key>
                <string>com.apple.finder</string>
            </dict>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.image</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# The shell command reads its input either way on purpose: Automator can hand a
# selection over as arguments or on standard input depending on how the action
# was built, and a Quick Action that silently does nothing is the worst outcome.
cat > "$SRV/Contents/document.wflow" <<WFLOW
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key><string>521</string>
    <key>AMApplicationVersion</key><string>2.10</string>
    <key>AMDocumentVersion</key><string>2</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMAccepts</key>
                <dict>
                    <key>Container</key><string>List</string>
                    <key>Optional</key><false/>
                    <key>Types</key><array><string>com.apple.cocoa.path</string></array>
                </dict>
                <key>AMActionVersion</key><string>2.0.3</string>
                <key>AMProvides</key>
                <dict>
                    <key>Container</key><string>List</string>
                    <key>Types</key><array><string>com.apple.cocoa.string</string></array>
                </dict>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key><string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>if [ \$# -gt 0 ]; then exec "$APP_DIR/jipeg.sh" "\$@"; else xargs -0 "$APP_DIR/jipeg.sh"; fi</string>
                    <key>CheckedForUserDefaultShell</key><true/>
                    <key>inputMethod</key><integer>1</integer>
                    <key>shell</key><string>/bin/bash</string>
                    <key>source</key><string></string>
                </dict>
                <key>BundleIdentifier</key>
                <string>com.apple.RunShellScript</string>
                <key>CFBundleVersion</key><string>2.0.3</string>
                <key>CanShowSelectedItemsWhenRun</key><false/>
                <key>CanShowWhenRun</key><true/>
                <key>Category</key><array><string>AMCategoryUtilities</string></array>
                <key>Class Name</key><string>RunShellScriptAction</string>
                <key>UUID</key><string>7D1B2A3C-4E5F-4A6B-8C9D-0E1F2A3B4C5D</string>
                <key>UnlocalizedApplications</key><array><string>Automator</string></array>
            </dict>
            <key>isViewVisible</key><integer>1</integer>
        </dict>
    </array>
    <key>connectors</key><dict/>
    <key>workflowMetaData</key>
    <dict>
        <key>serviceInputTypeIdentifier</key>
        <string>com.apple.Automator.fileSystemObject.image</string>
        <key>serviceOutputTypeIdentifier</key>
        <string>com.apple.Automator.nothing</string>
        <key>serviceApplicationBundleID</key>
        <string>com.apple.finder</string>
        <key>serviceApplicationPath</key>
        <string>/System/Library/CoreServices/Finder.app</string>
        <key>applicationBundleIDsByPath</key><dict/>
        <key>applicationPaths</key><array/>
        <key>workflowTypeIdentifier</key>
        <string>com.apple.Automator.servicesMenu</string>
    </dict>
</dict>
</plist>
WFLOW

# Tell the services system to look again, rather than waiting for a log-out.
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true

printf '\n'
say "Quick Action installed: $SRV"
say 'Right-click an image in Finder, then look under "Quick Actions".'
say 'If it is not there, enable it in System Settings > Keyboard >'
say 'Keyboard Shortcuts > Services, or log out and back in.'
printf '\n'
