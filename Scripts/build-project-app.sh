#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_bundle="$project_root/ContextCard.app"

cd "$project_root"
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$project_root/Packaging/ContextCard-Info.plist" "$app_bundle/Contents/Info.plist"
cp "$binary_directory/ContextCard" "$app_bundle/Contents/MacOS/ContextCard"
cp "$project_root/Assets/ContextCard.icns" "$app_bundle/Contents/Resources/ContextCard.icns"
codesign --force --deep --sign - "$app_bundle"

printf 'Built %s\n' "$app_bundle"
