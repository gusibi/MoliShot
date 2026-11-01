#!/bin/bash
set -euo pipefail
DEST="${1:?Usage: fetch-sparkle.sh destination}"
mkdir -p "$DEST"
ARCHIVE="$DEST/Sparkle-2.10.1.tar.xz"
curl --fail --location --retry 3 --proto '=https' \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz \
  --output "$ARCHIVE"
# Pinned upstream release asset; tools and embedded framework must stay in sync.
EXPECTED_SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
echo "$EXPECTED_SHA256  $ARCHIVE" | shasum -a 256 -c -
tar -xJf "$ARCHIVE" -C "$DEST"
