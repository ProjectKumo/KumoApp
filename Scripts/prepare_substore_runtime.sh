#!/usr/bin/env bash
set -euo pipefail

NODE_VERSION="${SUBSTORE_NODE_VERSION:-24.14.0}"
SUBSTORE_DIR="${SUBSTORE_DIR:-Sources/KumoCoreKit/Resources/SubStore}"
CACHE_DIR="${SUBSTORE_RUNTIME_CACHE_DIR:-build/substore-runtime-cache}"
NODE_TARGET="${SUBSTORE_DIR}/node/bin/node"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)
    NODE_PLATFORM="darwin-arm64"
    ;;
  Darwin-x86_64)
    NODE_PLATFORM="darwin-x64"
    ;;
  *)
    echo "Unsupported Sub-Store Node runtime platform: $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

if [[ -x "$NODE_TARGET" ]] && [[ "$("$NODE_TARGET" --version)" == "v${NODE_VERSION}" ]]; then
  exit 0
fi

ARCHIVE_NAME="node-v${NODE_VERSION}-${NODE_PLATFORM}.tar.xz"
ARCHIVE_PATH="${CACHE_DIR}/${ARCHIVE_NAME}"
EXTRACT_DIR="${CACHE_DIR}/node-v${NODE_VERSION}-${NODE_PLATFORM}"
DOWNLOAD_URL="${SUBSTORE_NODE_DOWNLOAD_URL:-https://nodejs.org/dist/v${NODE_VERSION}/${ARCHIVE_NAME}}"

mkdir -p "$CACHE_DIR"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  curl -fL "$DOWNLOAD_URL" -o "$ARCHIVE_PATH"
fi

rm -rf "$EXTRACT_DIR"
tar -xJf "$ARCHIVE_PATH" -C "$CACHE_DIR"

mkdir -p "$(dirname "$NODE_TARGET")"
cp "${EXTRACT_DIR}/bin/node" "$NODE_TARGET"
chmod 755 "$NODE_TARGET"

rm -rf "$EXTRACT_DIR"
