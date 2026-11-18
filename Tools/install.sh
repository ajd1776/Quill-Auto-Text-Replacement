#!/bin/zsh
# Builds a signed Release copy of Quill and installs it in /Applications.
# The first run lets Xcode create your free Apple Development certificate.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "Building Quill…"
xcodebuild -project Quill.xcodeproj -scheme Quill -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build.noindex -allowProvisioningUpdates build -quiet

echo "Installing to /Applications…"
pkill -x Quill 2>/dev/null || true
sleep 1
rm -rf /Applications/Quill.app
cp -R build.noindex/Build/Products/Release/Quill.app /Applications/
codesign -dv /Applications/Quill.app 2>&1 | grep -E "Authority=Apple Development|TeamIdentifier" || true
open /Applications/Quill.app
echo "Done. Quill is running from /Applications."
