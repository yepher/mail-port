#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
build_dir="${MAILPORT_BUILD_DIR:-$task_root/.build}"
dist_dir="${MAILPORT_DIST_DIR:-$task_root/dist}"
sign_identity="${MAILPORT_SIGN_IDENTITY:--}"
mkdir -p "$build_dir/ModuleCache" "$build_dir/Cache" "$build_dir/Configuration" "$build_dir/Security" "$dist_dir"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/ModuleCache"
swift_options=(--disable-sandbox --scratch-path "$build_dir" --cache-path "$build_dir/Cache" --config-path "$build_dir/Configuration" --security-path "$build_dir/Security")
if [[ "${1:-}" == "--test" ]]; then swift test "${swift_options[@]}"; fi
swift build "${swift_options[@]}" -c release
binary_dir="$(swift build "${swift_options[@]}" -c release --show-bin-path)"
mkdir -p "$build_dir/MailPort.iconset"
swift -module-cache-path "$build_dir/ModuleCache" scripts/make-icon.swift "$build_dir/MailPort.iconset" "$build_dir/MailPort.icns"
bundle="$dist_dir/MailPort.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/MailPort" "$bundle/Contents/MacOS/MailPort"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp "$build_dir/MailPort.icns" "$bundle/Contents/Resources/MailPort.icns"
cp README.md "$bundle/Contents/Resources/README.md"
cp Sources/MailPortEmbedded/Resources/NotificationBridge.js "$bundle/Contents/Resources/NotificationBridge.js"
cp Sources/MailPortEmbedded/Resources/TabActivity.js "$bundle/Contents/Resources/TabActivity.js"
chmod +x "$bundle/Contents/MacOS/MailPort"
plutil -lint "$bundle/Contents/Info.plist"
sign_options=(--force --options runtime --entitlements Resources/MailPort.entitlements --sign "$sign_identity")
if [[ "$sign_identity" != "-" ]]; then sign_options+=(--timestamp); fi
codesign "${sign_options[@]}" "$bundle"
codesign --verify --strict "$bundle"
file "$bundle/Contents/MacOS/MailPort"
printf '\nBuilt %s\n' "$bundle"
