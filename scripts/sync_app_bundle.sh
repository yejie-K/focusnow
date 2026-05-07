#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$repo_root/状态切换工具.app"
binary_src="$repo_root/.build/arm64-apple-macosx/debug/StateSwitchMenubar"
binary_dst="$app_path/Contents/MacOS/StateSwitchMenubar"
plist="$app_path/Contents/Info.plist"
resources_dir="$app_path/Contents/Resources"
icon_icns="$repo_root/assets/AppIcon.icns"

python3 "$repo_root/scripts/build_app_icon.py" >/dev/null
swift build --package-path "$repo_root" >/dev/null
mkdir -p "$resources_dir"
cp "$binary_src" "$binary_dst"
cp "$icon_icns" "$resources_dir/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.stateswitch.menubar" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.1.0" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 210" "$plist"
rm -f "$app_path/Icon"$'\r'
xattr -cr "$app_path"
codesign --force --deep --sign - --identifier local.stateswitch.menubar "$app_path" >/dev/null

echo "$app_path"
