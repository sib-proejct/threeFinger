#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
dist_dir="$project_root/dist"
app_bundle="$dist_dir/ThreeFingerMiddleClick.app"
dmg_path="$dist_dir/ThreeFingerMiddleClick.dmg"

"$project_root/scripts/build-app.sh"

dmg_staging="$(mktemp -d "$dist_dir/.ThreeFingerMiddleClick.dmg.XXXXXX")"
trap 'rm -rf "$dmg_staging"' EXIT

cp -R "$app_bundle" "$dmg_staging/ThreeFingerMiddleClick.app"
ln -s /Applications "$dmg_staging/Applications"
cp "$project_root/macos/INSTALL.txt" "$dmg_staging/설치 방법.txt"

rm -f "$dmg_path"
hdiutil create \
  -volname "ThreeFingerMiddleClick" \
  -srcfolder "$dmg_staging" \
  -format UDZO \
  -ov \
  "$dmg_path"

print "Built $dmg_path"
