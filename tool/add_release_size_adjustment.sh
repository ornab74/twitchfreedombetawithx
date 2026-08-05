#!/usr/bin/env bash
set -euo pipefail

bundle="${1:?usage: add_release_size_adjustment.sh BUNDLE}"
padding_bytes="${RELEASE_SIZE_ADJUSTMENT_BYTES:-2621440}"

if [[ ! -d "$bundle" ]]; then
  echo "Release bundle does not exist: $bundle" >&2
  exit 1
fi

# This inert, random payload keeps compressed/package sizes from landing on an
# undesirable boundary. It is deliberately outside the executable and is not
# read by the application.
mkdir -p "$bundle/.release"
dd if=/dev/urandom of="$bundle/.release/size-adjustment.bin" \
  bs=1 count="$padding_bytes" status=none
