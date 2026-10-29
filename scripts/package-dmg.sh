#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# LiveCore Studio for macOS — Reproducible DMG Packaging Script
# Target output: dist/LiveCore-Studio.dmg + dist/LiveCore-Studio.dmg.sha256
# ==============================================================================

APP_BUNDLE_PATH="${1:-build/DerivedData/Build/Products/Release/LiveCoreStudio.app}"
STAGING_DIR="build/dmg-staging"
DIST_DIR="dist"
DMG_NAME="LiveCore-Studio.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
VOLUME_NAME="LiveCore Studio"

echo "==> [1/7] Validating macOS host environment and hdiutil availability..."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: scripts/package-dmg.sh requires macOS (Darwin) with hdiutil." >&2
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "ERROR: hdiutil not found on PATH." >&2
  exit 1
fi

echo "==> [2/7] Verifying application bundle at: ${APP_BUNDLE_PATH}"
if [[ ! -d "${APP_BUNDLE_PATH}" ]]; then
  echo "ERROR: .app bundle directory does not exist at ${APP_BUNDLE_PATH}" >&2
  exit 2
fi

EXECUTABLE_PATH="${APP_BUNDLE_PATH}/Contents/MacOS/LiveCoreStudio"
INFO_PLIST_PATH="${APP_BUNDLE_PATH}/Contents/Info.plist"

if [[ ! -f "${EXECUTABLE_PATH}" ]]; then
  echo "ERROR: Mach-O executable missing at ${EXECUTABLE_PATH}" >&2
  exit 3
fi

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  chmod +x "${EXECUTABLE_PATH}"
fi

if [[ ! -f "${INFO_PLIST_PATH}" ]]; then
  echo "ERROR: Info.plist missing at ${INFO_PLIST_PATH}" >&2
  exit 4
fi

echo "    Verified Mach-O binary:"
file "${EXECUTABLE_PATH}"

echo "==> [3/7] Preparing clean staging directory: ${STAGING_DIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
mkdir -p "${DIST_DIR}"

echo "==> [4/7] Copying LiveCoreStudio.app and creating /Applications symlink..."
ditto "${APP_BUNDLE_PATH}" "${STAGING_DIR}/LiveCoreStudio.app"
ln -s /Applications "${STAGING_DIR}/Applications"

# Apply ad-hoc signature if no Developer ID certificate was injected so Gatekeeper metadata is structurally valid
if ! codesign -v "${STAGING_DIR}/LiveCoreStudio.app" >/dev/null 2>&1; then
  echo "    Applying ad-hoc code signature (-) to staged bundle..."
  codesign --force --deep --sign - "${STAGING_DIR}/LiveCoreStudio.app"
fi

echo "==> [5/7] Creating compressed UDZO disk image at ${DMG_PATH}..."
rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${DMG_PATH}"

echo "==> [6/7] Validating generated DMG file integrity and mountability..."
if [[ ! -s "${DMG_PATH}" ]]; then
  echo "ERROR: Generated DMG is missing or empty at ${DMG_PATH}" >&2
  exit 5
fi

hdiutil verify "${DMG_PATH}"
hdiutil imageinfo "${DMG_PATH}" | grep -E "Format|Class Name|Total Bytes" || true

MOUNT_OUTPUT="$(hdiutil attach -readonly -nobrowse -noverify "${DMG_PATH}")"
MOUNT_POINT="$(echo "${MOUNT_OUTPUT}" | tail -n 1 | awk -F'\t' '{print $NF}')"
echo "    Mounted DMG at: ${MOUNT_POINT}"

if [[ ! -d "${MOUNT_POINT}/LiveCoreStudio.app" ]]; then
  hdiutil detach "${MOUNT_POINT}" -force || true
  echo "ERROR: LiveCoreStudio.app not found inside mounted DMG!" >&2
  exit 6
fi

hdiutil detach "${MOUNT_POINT}"

echo "==> [7/7] Computing SHA-256 checksum..."
shasum -a 256 "${DMG_PATH}" | tee "${DMG_PATH}.sha256"
DMG_SIZE_BYTES="$(stat -f%z "${DMG_PATH}")"
echo "==> SUCCESS: ${DMG_PATH} (${DMG_SIZE_BYTES} bytes) packaged and verified."
