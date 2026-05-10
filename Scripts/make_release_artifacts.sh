#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:?Set VERSION, for example VERSION=0.0.1}"
CHANNEL="${CHANNEL:-stable}"
REPOSITORY="${REPOSITORY:-ProjectKumo/KumoApp}"
APP_PATH="${APP_PATH:-build/Build/Products/Release/Kumo.app}"
OUTPUT_DIR="${OUTPUT_DIR:-build/release}"
ARCH_NAME="${ARCH_NAME:-arm64}"
DMG_BACKGROUND_PATH="${DMG_BACKGROUND_PATH:-Assets/dmg-background.png}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-660}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-420}"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-96}"
DMG_ICON_Y="${DMG_ICON_Y:-220}"
DMG_APP_ICON_X="${DMG_APP_ICON_X:-176}"
DMG_APPLICATIONS_ICON_X="${DMG_APPLICATIONS_ICON_X:-488}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  echo "Run make app-release first." >&2
  exit 1
fi

if [[ ! -f "$DMG_BACKGROUND_PATH" ]]; then
  echo "DMG background not found: $DMG_BACKGROUND_PATH" >&2
  echo "Place the installer background at Assets/dmg-background.png." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

ASSET_NAME="Kumo-macos-${VERSION}-${ARCH_NAME}.dmg"
DMG_PATH="${OUTPUT_DIR}/${ASSET_NAME}"
RW_DMG_PATH="${OUTPUT_DIR}/${ASSET_NAME%.dmg}-rw.dmg"
MOUNT_DIR="$(mktemp -d /tmp/kumo-dmg-mount.XXXXXX)"
VOLUME_NAME="Kumo ${VERSION}"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" == "1" ]]; then
    hdiutil detach "$MOUNT_DIR" -force -quiet || true
  fi
  rm -rf "$MOUNT_DIR" "$RW_DMG_PATH"
}
trap cleanup EXIT

detach_dmg() {
  local attempt
  for attempt in 1 2 3 4 5; do
    if hdiutil detach "$MOUNT_DIR" -quiet; then
      MOUNTED=0
      return 0
    fi
    sleep 1
  done

  hdiutil detach "$MOUNT_DIR" -force -quiet
  MOUNTED=0
}

configure_finder_window() {
  /usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 100 + $DMG_WINDOW_WIDTH, 100 + $DMG_WINDOW_HEIGHT}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $DMG_ICON_SIZE
    set background picture of viewOptions to (POSIX file "$MOUNT_DIR/.background/dmg-background.png" as alias)
    set position of item "Kumo.app" of container window to {$DMG_APP_ICON_X, $DMG_ICON_Y}
    set position of item "Applications" of container window to {$DMG_APPLICATIONS_ICON_X, $DMG_ICON_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
}

APP_SIZE_MB="$(du -sm "$APP_PATH" | awk '{print $1}')"
DMG_SIZE_MB="$((APP_SIZE_MB + 128))"

rm -f "$DMG_PATH" "$RW_DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -size "${DMG_SIZE_MB}m" \
  -fs HFS+ \
  -ov \
  -type UDIF \
  "$RW_DMG_PATH"

hdiutil attach "$RW_DMG_PATH" \
  -readwrite \
  -noverify \
  -noautoopen \
  -mountpoint "$MOUNT_DIR" \
  -quiet
MOUNTED=1

ditto "$APP_PATH" "$MOUNT_DIR/Kumo.app"
ln -s /Applications "$MOUNT_DIR/Applications"
mkdir -p "$MOUNT_DIR/.background"
cp "$DMG_BACKGROUND_PATH" "$MOUNT_DIR/.background/dmg-background.png"

configure_finder_window
sync
detach_dmg

hdiutil convert "$RW_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_PATH" \
  -quiet

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

if [[ "$CHANNEL" == "beta" ]]; then
  RELEASE_TAG="pre-release"
else
  RELEASE_TAG="${VERSION}"
fi

DOWNLOAD_URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
MANIFEST_PATH="${OUTPUT_DIR}/latest.yml"

cat > "$MANIFEST_PATH" <<EOF
version: ${VERSION}
channel: ${CHANNEL}
downloadURL: ${DOWNLOAD_URL}
assetName: ${ASSET_NAME}
sha256: ${SHA256}
releaseNotes: |
  See https://github.com/${REPOSITORY}/releases/tag/${RELEASE_TAG}
EOF

echo "Created ${DMG_PATH}"
echo "Created ${MANIFEST_PATH}"
echo "SHA-256 ${SHA256}"
