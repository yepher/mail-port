#!/bin/bash
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
cache_dir="$task_root/.build/ModuleCache"
export CLANG_MODULE_CACHE_PATH="$cache_dir"
export SWIFT_MODULECACHE_PATH="$cache_dir"
export SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir"
mkdir -p "$cache_dir" "$task_root/dist" "$task_root/.build/Cache" \
  "$task_root/.build/Configuration" "$task_root/.build/Security"
swift_options=(--disable-sandbox --scratch-path "$task_root/.build" \
  --cache-path "$task_root/.build/Cache" \
  --config-path "$task_root/.build/Configuration" \
  --security-path "$task_root/.build/Security")

if [[ "${1:-}" == "--test" ]]; then
  swift test "${swift_options[@]}"
fi

swift build "${swift_options[@]}" -c release
binary_dir="$(swift build "${swift_options[@]}" -c release --show-bin-path)"
iconset="$task_root/.build/MailPort.iconset"
mkdir -p "$iconset"
swift -module-cache-path "$cache_dir" "$task_root/scripts/make-icon.swift" \
  "$iconset" "$task_root/.build/MailPort-fallback.icns"
if ! iconutil -c icns "$iconset" -o "$task_root/.build/MailPort.icns" \
  2>"$task_root/.build/iconutil.log"; then
  # iconutil uses a nested sandbox that some build environments prohibit.
  # The generator also writes the standard ICNS container directly from its PNGs.
  cp "$task_root/.build/MailPort-fallback.icns" "$task_root/.build/MailPort.icns"
  printf 'Using native ICNS packaging (iconutil was unavailable).\n'
fi

bundle="$task_root/dist/MailPort.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/MailPort" "$bundle/Contents/MacOS/MailPort"
cp "$task_root/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$task_root/.build/MailPort.icns" "$bundle/Contents/Resources/MailPort.icns"
cp "$task_root/README.md" "$bundle/Contents/Resources/README.md"
chmod +x "$bundle/Contents/MacOS/MailPort"
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
printf '\nBuilt %s\n' "$bundle"
file "$bundle/Contents/MacOS/MailPort"

