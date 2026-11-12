#!/bin/bash
# Compile SleepWithMe sans Xcode, avec les seuls outils en ligne de commande.
#   ./build.sh           compile et lance l'appli
#   ./build.sh install   compile, copie dans /Applications et lance
set -euo pipefail
cd "$(dirname "$0")"

APP="build/SleepWithMe.app"
ARCH="$(uname -m)"

SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)"
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
  echo "SDK macOS trouvé : $SDK_VERSION. Il faut le SDK 26 ou plus récent."
  echo "Mets à jour les outils : Réglages Système > Général > Mise à jour de logiciels,"
  echo "ou : sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
  exit 1
fi

# Ferme l'ancienne version si elle tourne.
pkill -x SleepWithMe 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "Compilation…"
xcrun swiftc -O -parse-as-library -swift-version 5 \
  -target "$ARCH-apple-macos26.0" \
  SleepWithMe/*.swift \
  -o "$APP/Contents/MacOS/SleepWithMe"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SleepWithMe</string>
  <key>CFBundleDisplayName</key><string>SleepWithMe</string>
  <key>CFBundleIdentifier</key><string>local.sleepwithme.SleepWithMe</string>
  <key>CFBundleExecutable</key><string>SleepWithMe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
touch "$APP"

if [ "${1:-}" = "install" ]; then
  rm -rf "/Applications/SleepWithMe.app"
  cp -R "$APP" "/Applications/SleepWithMe.app"
  APP="/Applications/SleepWithMe.app"
fi

echo "OK : $APP"
open "$APP"
