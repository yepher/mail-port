#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
build_dir="${MAILPORT_BUILD_DIR:-$task_root/.build}"
mkdir -p "$build_dir/ModuleCache" "$build_dir/Cache" "$build_dir/Configuration" "$build_dir/Security" "$task_root/dist"
export CLANG_MODULE_CACHE_PATH="$build_dir/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/ModuleCache"
swift_options=(--disable-sandbox --scratch-path "$build_dir" --cache-path "$build_dir/Cache" --config-path "$build_dir/Configuration" --security-path "$build_dir/Security")
if [[ "${1:-}" == "--test" ]]; then swift test "${swift_options[@]}"; fi
swift build "${swift_options[@]}" -c release
binary_dir="$(swift build "${swift_options[@]}" -c release --show-bin-path)"
mkdir -p "$build_dir/MailPort.iconset"
swift -module-cache-path "$build_dir/ModuleCache" scripts/make-icon.swift "$build_dir/MailPort.iconset" "$build_dir/MailPort.icns"
bundle="$task_root/dist/MailPort Preview.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/MailPortPreview" "$bundle/Contents/MacOS/MailPortPreview"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp "$build_dir/MailPort.icns" "$bundle/Contents/Resources/MailPort.icns"
cp README.md "$bundle/Contents/Resources/README.md"
chmod +x "$bundle/Contents/MacOS/MailPortPreview"
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
file "$bundle/Contents/MacOS/MailPortPreview"
printf '\nBuilt %s\n' "$bundle"
