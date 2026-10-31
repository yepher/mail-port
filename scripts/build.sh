#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
build_dir="${MAILPORT_BUILD_DIR:-$task_root/.build}"
dist_dir="${MAILPORT_DIST_DIR:-$task_root/dist}"
sign_identity="${MAILPORT_SIGN_IDENTITY:--}"
release_repo="${MAILPORT_RELEASE_REPO:-yepher/mail-port}"
sparkle_public_key="67Qko3bJ0fovyqrRGjQ9XUcZaAfpWfjMSr/3O161awo="
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
install_name_tool -add_rpath "@executable_path/../Frameworks" "$bundle/Contents/MacOS/MailPort"
rm -rf "$bundle/Contents/Frameworks"
mkdir -p "$bundle/Contents/Frameworks"
ditto "$binary_dir/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.chriswilson.mailport.embedded "$bundle/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string MailPort "$bundle/Contents/Info.plist"
# Only signed builds get the update feed, so a local build is never replaced by a release.
if [[ "$sign_identity" != "-" ]]; then
    plutil -replace SUFeedURL -string "https://github.com/$release_repo/releases/latest/download/appcast.xml" "$bundle/Contents/Info.plist"
    plutil -replace SUPublicEDKey -string "$sparkle_public_key" "$bundle/Contents/Info.plist"
    plutil -replace SUEnableAutomaticChecks -bool true "$bundle/Contents/Info.plist"
fi
cp "$build_dir/MailPort.icns" "$bundle/Contents/Resources/MailPort.icns"
cp README.md "$bundle/Contents/Resources/README.md"
cp Sources/MailPortEmbedded/Resources/NotificationBridge.js "$bundle/Contents/Resources/NotificationBridge.js"
cp Sources/MailPortEmbedded/Resources/TabActivity.js "$bundle/Contents/Resources/TabActivity.js"
chmod +x "$bundle/Contents/MacOS/MailPort"
plutil -lint "$bundle/Contents/Info.plist"
# Hardened apps only load frameworks from their own team, which a local signature doesn't have.
helper_options=(--force --sign "$sign_identity")
if [[ "$sign_identity" != "-" ]]; then helper_options+=(--options runtime --timestamp); fi
# Notarization needs every nested helper signed by this identity, innermost first.
sparkle="$bundle/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${helper_options[@]}" "$sparkle/XPCServices/Installer.xpc"
codesign "${helper_options[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
codesign "${helper_options[@]}" "$sparkle/Autoupdate"
codesign "${helper_options[@]}" "$sparkle/Updater.app"
codesign "${helper_options[@]}" "$bundle/Contents/Frameworks/Sparkle.framework"
codesign "${helper_options[@]}" --entitlements Resources/MailPort.entitlements "$bundle"
codesign --verify --strict --deep "$bundle"
file "$bundle/Contents/MacOS/MailPort"
printf '\nBuilt %s\n' "$bundle"
