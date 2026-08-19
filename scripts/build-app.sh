#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
dist_dir="$project_root/dist"
final_bundle="$dist_dir/3F.app"
module_cache="$project_root/target/swift-module-cache"
clang_module_cache="$project_root/target/clang-module-cache"
sdk_module_cache="$project_root/target/sdk-module-cache"
# Use an ad-hoc signature for local builds. Set this to a Developer ID
# Application certificate name for distribution, for example:
# CODESIGN_IDENTITY='Developer ID Application: Example, Inc. (TEAMID)'
codesign_identity="${CODESIGN_IDENTITY:--}"

cd "$project_root"

if ! command -v cargo >/dev/null 2>&1; then
  print -u2 "Rust is required. Install it with: brew install rust"
  exit 1
fi

cargo build --release
mkdir -p "$dist_dir" "$module_cache" "$clang_module_cache" "$sdk_module_cache"
staging_dir="$(mktemp -d "$dist_dir/.3F.build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

app_bundle="$staging_dir/3F.app"
binary_dir="$app_bundle/Contents/MacOS"
resources_dir="$app_bundle/Contents/Resources"
iconset_dir="$staging_dir/AppIcon.iconset"
mkdir -p "$binary_dir" "$resources_dir"
cp macos/Info.plist "$app_bundle/Contents/Info.plist"

swift scripts/generate-app-icon.swift "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$resources_dir/AppIcon.icns"

CLANG_MODULE_CACHE_PATH="$clang_module_cache" swiftc \
  -parse-as-library \
  -target arm64-apple-macos13.0 \
  -module-cache-path "$module_cache" \
  -sdk-module-cache-path "$sdk_module_cache" \
  -clang-scanner-module-cache-path "$clang_module_cache" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -L target/release \
  -lthree_finger_middle_click \
  macos/ThreeFingerMiddleClickApp.swift \
  -o "$binary_dir/3F"

# Sign the completed bundle rather than relying on the executable-only ad-hoc
# signature emitted by the linker. A Developer ID release also enables the
# hardened runtime and a secure timestamp, which are required for notarization.
codesign_args=(--force --sign "$codesign_identity")
if [[ "$codesign_identity" != "-" ]]; then
  codesign_args+=(--options runtime --timestamp)
fi
codesign "${codesign_args[@]}" "$app_bundle"
codesign --verify --deep --strict --verbose=2 "$app_bundle"

rm -rf "$final_bundle"
mv "$app_bundle" "$final_bundle"
print "Built $final_bundle"
