#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
app_dir="$project_dir/RapooFlow.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"

export CLANG_MODULE_CACHE_PATH=/private/tmp/rapooflow-clang-cache
export SWIFT_MODULE_CACHE_PATH=/private/tmp/rapooflow-swift-cache
swiftc -O -warnings-as-errors \
  "$project_dir/Sources/Preferences.swift" \
  "$project_dir/Sources/ScrollMotion.swift" \
  "$project_dir/Sources/InputEngine.swift" \
  "$project_dir/Sources/main.swift" \
  -framework AppKit -framework ApplicationServices -framework IOKit -framework CoreVideo \
  -o "$app_dir/Contents/MacOS/RapooFlow"
codesign --force --sign - "$app_dir"
echo "$app_dir"
