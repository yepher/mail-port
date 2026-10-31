#!/bin/bash
# Builds, signs, notarizes, and publishes MailPort to GitHub Releases.
#
#   ./scripts/release.sh             Release the next patch version after the latest tag
#   ./scripts/release.sh 0.7.0       Bump to 0.7.0, then release it
#   ./scripts/release.sh --dry-run   Build and package only; no Apple or GitHub steps
#
# Setup and environment overrides are described in CONTRIBUTING.md under Release.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"

plist="Resources/Info.plist"
repo="${MAILPORT_RELEASE_REPO:-yepher/mail-port}"
notary_profile="${MAILPORT_NOTARY_PROFILE:-mailport-notary}"
sparkle_account="${MAILPORT_SPARKLE_ACCOUNT:-mailport}"
sparkle_bin="${MAILPORT_BUILD_DIR:-$task_root/.build}/artifacts/sparkle/Sparkle/bin"
release_dir="$task_root/dist/release"

fail() { printf 'release: %s\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

dry_run=false
version=""
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=true ;;
        -*) fail "unknown option $arg" ;;
        *) [[ -z "$version" ]] || fail "only one version may be given"; version="$arg" ;;
    esac
done

current_version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
current_build="$(plutil -extract CFBundleVersion raw "$plist")"

latest_version() { git tag --list 'v0.*' | sed -n 's/^v\(0\.[0-9]*\.[0-9]*\)$/\1/p' | sort -V | tail -1; }

# Without a version, add one to the latest release. An unreleased higher version
# already set in Info.plist wins, so the version never moves backward.
next_version() {
    local latest
    latest="$(latest_version)"
    if [[ -z "$latest" ]]; then printf '%s\n' "$current_version"; return; fi
    local next="${latest%.*}.$((${latest##*.} + 1))"
    printf '%s\n%s\n' "$next" "$current_version" | sort -V | tail -1
}

if [[ -z "$version" ]]; then
    git fetch --quiet origin --tags 2>/dev/null || $dry_run || fail "couldn't read release tags from origin"
    version="$(next_version)"
fi
[[ "$version" =~ ^0\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 0.x.y, got '$version'"
tag="v$version"

step "Checking prerequisites for $version"
if $dry_run; then
    sign_identity="-"
else
    sign_identity="${MAILPORT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)}"
    [[ -n "$sign_identity" ]] || fail "no valid Developer ID Application certificate in the Keychain (see CONTRIBUTING.md, Release)"
    xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 || fail "notary profile '$notary_profile' is missing or rejected (see CONTRIBUTING.md, Release)"
    gh auth status >/dev/null 2>&1 || fail "gh is not logged in"
    [[ -z "$(git status --porcelain)" ]] || fail "working tree has uncommitted changes"
    [[ "$(git branch --show-current)" == "main" ]] || fail "releases are cut from main"
    git fetch --quiet origin main --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not in sync with origin/main"
    ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || fail "tag $tag already exists; choose a new version"
fi

start_commit="$(git rev-parse HEAD)"
work_dir="$(mktemp -d)"
plist_backup="$work_dir/Info.plist"
cp "$plist" "$plist_backup"
restore_plist=true
cleanup() {
    if $restore_plist; then cp "$plist_backup" "$plist"; fi
    rm -rf "$work_dir"
}
trap cleanup EXIT

# Sparkle compares build numbers, so a release must always raise it or nobody is offered the update.
build="$current_build"
[[ "$version" == "$current_version" ]] || build=$((build + 1))
last_version="$(latest_version)"
if [[ -n "$last_version" ]]; then
    last_build="$(git show "v$last_version:$plist" | sed -n '/CFBundleVersion/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}')"
    if [[ "$last_build" =~ ^[0-9]+$ ]] && (( build <= last_build )); then build=$((last_build + 1)); fi
fi
if [[ "$version" != "$current_version" || "$build" != "$current_build" ]]; then
    step "Setting version $version, build $build"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $build" "$plist"
fi

step "Building and testing $version"
rm -rf "$release_dir"
for script_test in scripts/test-*.cjs; do node "$script_test"; done
MAILPORT_DIST_DIR="$release_dir" MAILPORT_SIGN_IDENTITY="$sign_identity" ./scripts/build.sh --test
if ! $dry_run; then
    "$sparkle_bin/generate_keys" --account "$sparkle_account" -p >/dev/null 2>&1 || fail "no Sparkle signing key '$sparkle_account' in the Keychain (see CONTRIBUTING.md, Release)"
fi
app="$release_dir/MailPort.app"
architecture="$(lipo -archs "$app/Contents/MacOS/MailPort" | tr ' ' '-')"
dmg="$release_dir/MailPort-$version-$architecture.dmg"

notarize() {
    local result="$work_dir/notary.json"
    xcrun notarytool submit "$1" --keychain-profile "$notary_profile" --wait --output-format json >"$result" || true
    local submission status
    submission="$(plutil -extract id raw "$result" 2>/dev/null || true)"
    status="$(plutil -extract status raw "$result" 2>/dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        [[ -z "$submission" ]] || xcrun notarytool log "$submission" --keychain-profile "$notary_profile" >&2 || true
        fail "notarization of $(basename "$1") ended with status '${status:-unknown}'"
    fi
}

# The app is stapled before packaging so it still opens offline once copied out of the disk image.
if ! $dry_run; then
    step "Notarizing the app"
    ditto -c -k --keepParent "$app" "$work_dir/MailPort.zip"
    notarize "$work_dir/MailPort.zip"
    xcrun stapler staple "$app"
fi

step "Creating the disk image"
stage="$work_dir/stage"
mkdir -p "$stage"
ditto "$app" "$stage/MailPort.app"
ln -s /Applications "$stage/Applications"
hdiutil create -quiet -volname "MailPort $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"

if $dry_run; then
    codesign --verify --strict "$app"
    hdiutil verify -quiet "$dmg"
    printf '\nDry run complete: %s\n' "$dmg"
    exit 0
fi

step "Notarizing the disk image"
codesign --force --sign "$sign_identity" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

step "Verifying Gatekeeper acceptance"
codesign --verify --strict --deep "$app"
spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
xcrun stapler validate "$dmg"

step "Writing the update feed"
# Sparkle reads this from the latest GitHub release, so publishing it is what offers the update.
dmg_name="$(basename "$dmg")"
sparkle_signature="$("$sparkle_bin/sign_update" --account "$sparkle_account" "$dmg")"
signature_value="$(printf '%s' "$sparkle_signature" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')"
[[ -n "$signature_value" ]] || fail "sign_update returned no signature"
"$sparkle_bin/sign_update" --verify --account "$sparkle_account" "$dmg" "$signature_value" >/dev/null || fail "the update signature didn't verify"
previous_tag="$(git describe --tags --abbrev=0 --match 'v0.*' HEAD 2>/dev/null || true)"
changes="$(git log --format=%s ${previous_tag:+"$previous_tag..HEAD"} | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/.*/<li>&<\/li>/')"
minimum_system="$(plutil -extract LSMinimumSystemVersion raw "$plist")"
appcast="$release_dir/appcast.xml"
cat >"$appcast" <<APPCAST
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>MailPort</title>
        <link>https://github.com/$repo</link>
        <item>
            <title>Version $version</title>
            <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
            <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
            <description><![CDATA[<ul>
$changes
</ul>]]></description>
            <enclosure url="https://github.com/$repo/releases/download/$tag/$dmg_name" type="application/x-apple-diskimage" $sparkle_signature/>
        </item>
    </channel>
</rss>
APPCAST
xmllint --noout "$appcast"

step "Publishing $tag to $repo"
# The tag must name what was built, so only a version bump may land during a run.
git diff --quiet "$start_commit" HEAD -- . ":(exclude)$plist" || fail "other commits landed during this run; run it again so the release includes them"
git add "$plist"
git diff --cached --quiet -- "$plist" || git commit --quiet -m "Release $version"
restore_plist=false
git tag -a "$tag" -m "MailPort $version"
git push --quiet --atomic origin main "$tag"

checksum="$(shasum -a 256 "$dmg" | cut -d ' ' -f 1)"
notes="MailPort is a compatibility preview. It requires macOS 14 or later on $architecture.

Open the disk image and drag MailPort to Applications.

SHA-256 of $(basename "$dmg"): \`$checksum\`"
gh release create "$tag" "$dmg" "$appcast" --repo "$repo" --verify-tag --title "MailPort $version" --notes "$notes" --generate-notes \
    || fail "$tag was pushed but the release failed; retry with: gh release create $tag '$dmg' '$appcast' --repo $repo --verify-tag --generate-notes"

printf '\nPublished %s\n' "$(gh release view "$tag" --repo "$repo" --json url --jq .url)"
