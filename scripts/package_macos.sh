#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
MACOS_DEVELOPER_DIR=${MACOS_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
SIGN_IDENTITY=${SIGN_IDENTITY:-}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_DIR}/build}
APP_DIR=${OUTPUT_DIR}/PaceBack.app
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "${PROJECT_DIR}/packaging/Info.plist")
ZIP_PATH=${OUTPUT_DIR}/PaceBack-${APP_VERSION}-macOS-universal.zip
ARM_BUILD_DIR=${PROJECT_DIR}/macos/.build/package-arm64
INTEL_BUILD_DIR=${PROJECT_DIR}/macos/.build/package-x86_64

if [[ ! -d ${MACOS_DEVELOPER_DIR} ]]; then
  print -u2 "MACOS_DEVELOPER_DIR must point to installed macOS Command Line Tools."
  exit 2
fi
export DEVELOPER_DIR=${MACOS_DEVELOPER_DIR}

# Prefer a stable Apple Development identity when one is installed. Stable
# signing preserves access to existing Keychain items across rebuilds. An
# ad-hoc signature is only a fallback for machines without a signing identity.
if [[ -z ${SIGN_IDENTITY} ]]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1)
fi
SIGN_IDENTITY=${SIGN_IDENTITY:--}

# Build both supported Mac architectures with Command Line Tools, then merge
# them into one distributable executable. No Xcode project or simulator is used.
swift build --package-path "${PROJECT_DIR}/macos" --scratch-path "${ARM_BUILD_DIR}" \
  -c release --arch arm64 --product PaceBack
swift build --package-path "${PROJECT_DIR}/macos" --scratch-path "${INTEL_BUILD_DIR}" \
  -c release --arch x86_64 --product PaceBack

rm -rf "${APP_DIR}"
mkdir -p \
  "${APP_DIR}/Contents/MacOS" \
  "${APP_DIR}/Contents/Resources/PaceBackEvidence"

lipo -create \
  "${ARM_BUILD_DIR}/arm64-apple-macosx/release/PaceBack" \
  "${INTEL_BUILD_DIR}/x86_64-apple-macosx/release/PaceBack" \
  -output "${APP_DIR}/Contents/MacOS/PaceBack"
cp "${PROJECT_DIR}/packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/packaging/PaceBack.icns" \
  "${APP_DIR}/Contents/Resources/PaceBack.icns"
cp "${PROJECT_DIR}/LICENSE" "${APP_DIR}/Contents/Resources/LICENSE"
cp "${PROJECT_DIR}/NOTICE" "${APP_DIR}/Contents/Resources/NOTICE"
cp "${PROJECT_DIR}/docs/mental_wellbeing_evidence_contract.md" \
  "${APP_DIR}/Contents/Resources/PaceBackEvidence/"
cp "${PROJECT_DIR}/docs/mental_wellbeing_game_research.md" \
  "${APP_DIR}/Contents/Resources/PaceBackEvidence/"
cp "${PROJECT_DIR}/docs/clinical_limitations.md" \
  "${APP_DIR}/Contents/Resources/PaceBackEvidence/"
cp "${PROJECT_DIR}/docs/competitive_ux_research.md" \
  "${APP_DIR}/Contents/Resources/PaceBackEvidence/"

if [[ ${SIGN_IDENTITY} == "-" ]]; then
  SIGN_FLAGS=(--force --sign - --timestamp=none)
else
  SIGN_FLAGS=(--force --sign "${SIGN_IDENTITY}" --options runtime --timestamp)
fi

codesign "${SIGN_FLAGS[@]}" "${APP_DIR}/Contents/MacOS/PaceBack"
codesign "${SIGN_FLAGS[@]}" --entitlements "${PROJECT_DIR}/packaging/PaceBack.entitlements" \
  "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

rm -f "${ZIP_PATH}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"
ZIP_SHA256=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')

print "Built standalone native wellbeing app at ${APP_DIR}"
print "Created release archive at ${ZIP_PATH}"
print "SHA-256: ${ZIP_SHA256}"
