#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_path="$repo_root/状态切换工具.app"
binary_src="$repo_root/.build/arm64-apple-macosx/debug/StateSwitchMenubar"
binary_dst="$app_path/Contents/MacOS/StateSwitchMenubar"
plist="$app_path/Contents/Info.plist"
resources_dir="$app_path/Contents/Resources"
icon_icns="$repo_root/assets/AppIcon.icns"
bundle_id="local.stateswitch.menubar"
version="2.4.0"
build_number="2400"

clear_codesign_detritus() {
  xattr -cr "$app_path" >/dev/null 2>&1 || true
  xattr -dr com.apple.FinderInfo "$app_path" >/dev/null 2>&1 || true
  xattr -dr 'com.apple.fileprovider.fpfs#P' "$app_path" >/dev/null 2>&1 || true
  xattr -d com.apple.FinderInfo "$app_path" >/dev/null 2>&1 || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$app_path" >/dev/null 2>&1 || true
  /usr/bin/SetFile -a b "$app_path" >/dev/null 2>&1 || true
  xattr -d com.apple.FinderInfo "$app_path" >/dev/null 2>&1 || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$app_path" >/dev/null 2>&1 || true
}

python3 "$repo_root/scripts/build_app_icon.py" >/dev/null
swift build --package-path "$repo_root" >/dev/null
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$resources_dir"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>StateSwitchMenubar</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>状态切换工具</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$version</string>
  <key>CFBundleVersion</key>
  <string>$build_number</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST
printf "APPL????" > "$app_path/Contents/PkgInfo"
cp "$binary_src" "$binary_dst"
cp "$icon_icns" "$resources_dir/AppIcon.icns"
rm -f "$app_path/Icon"$'\r'

clear_codesign_detritus
sleep 0.2
clear_codesign_detritus
if ! codesign --force --deep --sign - --identifier "$bundle_id" "$app_path" >/dev/null 2>&1; then
  sleep 0.3
  clear_codesign_detritus
  codesign --force --deep --sign - --identifier "$bundle_id" "$app_path" >/dev/null 2>&1
fi
clear_codesign_detritus
if ! codesign --verify --deep --strict "$app_path" >/dev/null 2>&1; then
  sleep 0.3
  clear_codesign_detritus
  codesign --force --deep --sign - --identifier "$bundle_id" "$app_path" >/dev/null 2>&1
  clear_codesign_detritus
  codesign --verify --deep --strict "$app_path" >/dev/null
fi

echo "$app_path"
