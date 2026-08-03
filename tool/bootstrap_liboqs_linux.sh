#!/usr/bin/env bash
set -euo pipefail

readonly LIBOQS_VERSION='0.15.0'
readonly LIBOQS_COMMIT='97f6b86b1b6d109cfd43cf276ae39c2e776aed80'
readonly PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SOURCE_DIR="${TMPDIR:-/tmp}/twitchfreedom-liboqs-${LIBOQS_VERSION}"
readonly BUILD_DIR="${TMPDIR:-/tmp}/twitchfreedom-liboqs-build-${LIBOQS_VERSION}"
readonly OUTPUT_DIR="${PROJECT_ROOT}/native/linux"

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
  git clone --filter=blob:none https://github.com/open-quantum-safe/liboqs.git "${SOURCE_DIR}"
fi
git -C "${SOURCE_DIR}" fetch --depth 1 origin "${LIBOQS_COMMIT}"
git -C "${SOURCE_DIR}" checkout --detach "${LIBOQS_COMMIT}"

cmake -S "${SOURCE_DIR}" -B "${BUILD_DIR}" -GNinja \
  -DBUILD_SHARED_LIBS=ON \
  -DOQS_BUILD_ONLY_LIB=ON \
  -DOQS_MINIMAL_BUILD=KEM_ml_kem_768 \
  -DOQS_DIST_BUILD=ON \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "${BUILD_DIR}" --parallel

mkdir -p "${OUTPUT_DIR}"
install -m 0755 "${BUILD_DIR}/lib/liboqs.so.${LIBOQS_VERSION}" \
  "${OUTPUT_DIR}/liboqs.so"
sha256sum "${OUTPUT_DIR}/liboqs.so"
echo "Bundled liboqs ${LIBOQS_VERSION} (${LIBOQS_COMMIT}) with ML-KEM-768 only."
