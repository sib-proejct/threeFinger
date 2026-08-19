#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
dist_dir="$project_root/dist"
final_bundle="$dist_dir/ThreeFingerMiddleClick.app"
module_cache="$project_root/target/swift-module-cache"

cd "$project_root"

if ! command -v cargo >/dev/null 2>&1; then
  print -u2 "Rust is required. Install it with: brew install rust"
  exit 1
fi

cargo build --release
mkdir -p "$dist_dir" "$module_cache"
staging_dir="$(mktemp -d "$dist_dir/.ThreeFingerMiddleClick.build.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT

app_bundle="$staging_dir/ThreeFingerMiddleClick.app"
binary_dir="$app_bundle/Contents/MacOS"
resources_dir="$app_bundle/Contents/Resources"
iconset_dir="$staging_dir/AppIcon.iconset"
mkdir -p "$binary_dir" "$resources_dir"
cp macos/Info.plist "$app_bundle/Contents/Info.plist"

swift scripts/generate-app-icon.swift "$iconset_dir"
iconutil -c icns "$iconset_dir" -o "$resources_dir/AppIcon.icns"

swiftc \
  -parse-as-library \
  -target arm64-apple-macos13.0 \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -L target/release \
  -lthree_finger_middle_click \
  macos/ThreeFingerMiddleClickApp.swift \
  -o "$binary_dir/ThreeFingerMiddleClick"

# Sign the completed bundle rather than relying on the executable-only ad-hoc
# signature emitted by the linker. This seals Info.plist as part of the app and
# keeps macOS permission and login-item checks consistent.
codesign --force --deep --sign - "$app_bundle"

rm -rf "$final_bundle"
mv "$app_bundle" "$final_bundle"
print "Built $final_bundle"
