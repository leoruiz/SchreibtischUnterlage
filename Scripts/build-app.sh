#!/bin/zsh

set -euo pipefail

root_directory=${0:A:h:h}
configuration=${CONFIGURATION:-debug}
app_directory="$root_directory/.build/Schreibtischunterlage.app"
contents_directory="$app_directory/Contents"
executable_directory="$contents_directory/MacOS"

swift build \
    --package-path "$root_directory" \
    --configuration "$configuration" \
    --arch arm64

binary_directory=$(
    swift build \
        --package-path "$root_directory" \
        --configuration "$configuration" \
        --arch arm64 \
        --show-bin-path
)

rm -rf "$app_directory"
mkdir -p "$executable_directory"
cp "$root_directory/Resources/Info.plist" "$contents_directory/Info.plist"
cp "$binary_directory/Schreibtischunterlage" "$executable_directory/Schreibtischunterlage"

codesign \
    --force \
    --sign "${CODESIGN_IDENTITY:--}" \
    --timestamp=none \
    "$app_directory"

echo "$app_directory"

