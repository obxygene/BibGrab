#!/bin/bash
# Build BibGrab.app into build/. Re-run after editing main.swift.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="${BIBGRAB_OUTPUT_APP:-$SRC/build/BibGrab.app}"
MACOS="$APP/Contents/MacOS"

mkdir -p "$MACOS" "$APP/Contents/Resources"

swiftc -O \
  -target "${BIBGRAB_ARCH:-$(uname -m)}-apple-macos13.0" \
  -framework Cocoa -framework Security -framework ServiceManagement \
  -o "$MACOS/BibGrab" \
  "$SRC/main.swift"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>BibGrab</string>
  <key>CFBundleDisplayName</key>     <string>BibGrab</string>
  <key>CFBundleIdentifier</key>      <string>org.bibgrab.BibGrab</string>
  <key>CFBundleExecutable</key>      <string>BibGrab</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleVersion</key>         <string>1</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Optional Developer ID signing for distribution; local builds use ad-hoc signing.
if [[ -n "${BIBGRAB_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$BIBGRAB_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "built: $APP"
