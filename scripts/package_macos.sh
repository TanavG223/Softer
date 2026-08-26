#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
ENGINE_PYTHON=${ENGINE_PYTHON:-${PROJECT_DIR}/.venv/bin/python}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
OUTPUT_DIR=${OUTPUT_DIR:-${PROJECT_DIR}/build}
APP_DIR=${OUTPUT_DIR}/PaceBack.app
HELPER_BUILD=${OUTPUT_DIR}/pyinstaller
MODEL_PACK_SOURCE=${MODEL_PACK_SOURCE:-${OUTPUT_DIR}/model-pack}
MODEL_TRUST_KEY_FILE=${MODEL_TRUST_KEY_FILE:-${OUTPUT_DIR}/model-pack-trust-key.b64}
DEMO_PLAN_DIR=${OUTPUT_DIR}/PaceBack-Demo-Plans
EVIDENCE_RESOURCES=${APP_DIR}/Contents/Resources/PaceBackEvidence

if [[ ! -x ${ENGINE_PYTHON} ]]; then
  print -u2 "ENGINE_PYTHON must point to Python 3.11-3.13 with engine[packaging,ml] installed."
  exit 2
fi

if [[ ! -f ${MODEL_PACK_SOURCE}/manifest.json || ! -f ${MODEL_TRUST_KEY_FILE} ]]; then
  print -u2 "A signed PaceBack model pack and separate trust key are required for packaging."
  exit 2
fi

"${ENGINE_PYTHON}" - "${PROJECT_DIR}/engine/requirements-release.lock" <<'PY'
import importlib.util
import importlib.metadata
import re
import sys
from pathlib import Path

required = (
    "PyInstaller",
    "cryptography",
    "numpy",
    "onnxruntime",
    "paceback_engine",
    "sqlcipher3",
    "tokenizers",
)
missing = [name for name in required if importlib.util.find_spec(name) is None]
if missing:
    raise SystemExit("Missing packaging dependencies: " + ", ".join(missing))
if not ((3, 11) <= sys.version_info[:2] < (3, 14)):
    raise SystemExit("PaceBack helper packaging requires Python 3.11-3.13")

lock_path = Path(sys.argv[1])
if not lock_path.is_file():
    raise SystemExit("The hash-locked release dependency file is missing")
pins = {}
for line in lock_path.read_text(encoding="utf-8").splitlines():
    match = re.match(r"^([A-Za-z0-9_.-]+)==([^ \\\t]+)", line)
    if match:
        normalized = re.sub(r"[-_.]+", "-", match.group(1)).lower()
        pins[normalized] = match.group(2)
mismatches = []
for package, expected in sorted(pins.items()):
    try:
        installed = importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        mismatches.append(f"{package}: missing (expected {expected})")
        continue
    if installed != expected:
        mismatches.append(f"{package}: {installed} (expected {expected})")
if mismatches:
    raise SystemExit(
        "Packaging environment does not match requirements-release.lock:\n"
        + "\n".join(mismatches)
    )
PY

mkdir -p "${OUTPUT_DIR}"
rm -rf "${APP_DIR}" "${HELPER_BUILD}"
mkdir -p \
  "${APP_DIR}/Contents/MacOS" \
  "${APP_DIR}/Contents/Helpers" \
  "${APP_DIR}/Contents/Resources"

swift build --package-path "${PROJECT_DIR}/macos" -c release --arch arm64
cp "${PROJECT_DIR}/macos/.build/arm64-apple-macosx/release/PaceBack" \
  "${APP_DIR}/Contents/MacOS/PaceBack"
cp "${PROJECT_DIR}/packaging/Info.plist" "${APP_DIR}/Contents/Info.plist"
cp "${PROJECT_DIR}/packaging/PaceBack.icns" \
  "${APP_DIR}/Contents/Resources/PaceBack.icns"
ditto "${MODEL_PACK_SOURCE}" "${APP_DIR}/Contents/Resources/PaceBackModelPack"
cp "${MODEL_TRUST_KEY_FILE}" \
  "${APP_DIR}/Contents/Resources/PaceBackModelTrustKey.b64"
cp "${PROJECT_DIR}/engine/MODEL_PROVENANCE.md" \
  "${APP_DIR}/Contents/Resources/MODEL_PROVENANCE.md"
cp "${PROJECT_DIR}/NOTICE" "${APP_DIR}/Contents/Resources/NOTICE"
mkdir -p "${APP_DIR}/Contents/Resources/ThirdPartyModelLicenses"
cp "${PROJECT_DIR}/third_party/model_licenses/"*.txt \
  "${APP_DIR}/Contents/Resources/ThirdPartyModelLicenses/"
mkdir -p "${APP_DIR}/Contents/Resources/ThirdPartySoftwareLicenses"
cp "${PROJECT_DIR}/third_party/software_licenses/"*.txt \
  "${APP_DIR}/Contents/Resources/ThirdPartySoftwareLicenses/"
mkdir -p "${EVIDENCE_RESOURCES}"
cp "${PROJECT_DIR}/engine/requirements-release.lock" "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/engine/sbom-release.cdx.json" "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/engine/pip-audit-2026-08-25.json" "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/engine/real-model-smoke-2026-08-25.json" "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/docs/evidence_manifest.json" "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/docs/clinical_limitations.md" "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/benchmark/results/full_real_models_unreviewed_unmeasured_2026-08-25-v2.summary.json" \
  "${EVIDENCE_RESOURCES}/"
cp "${PROJECT_DIR}/benchmark/results/full_real_models_unreviewed_unmeasured_2026-08-25-v2.jsonl.metadata.json" \
  "${EVIDENCE_RESOURCES}/"

PYINSTALLER_SIGNING=(
  --osx-entitlements-file "${PROJECT_DIR}/packaging/Sidecar.entitlements"
)
if [[ ${SIGN_IDENTITY} != "-" ]]; then
  PYINSTALLER_SIGNING+=(--codesign-identity "${SIGN_IDENTITY}")
fi

"${ENGINE_PYTHON}" -m PyInstaller \
  --noconfirm \
  --clean \
  --onedir \
  --windowed \
  --target-arch arm64 \
  --name paceback-engine \
  --osx-bundle-identifier org.hackforhumanity.paceback.engine \
  --distpath "${HELPER_BUILD}/dist" \
  --workpath "${HELPER_BUILD}/work" \
  --specpath "${HELPER_BUILD}" \
  --hidden-import sqlcipher3 \
  --hidden-import cryptography \
  --hidden-import numpy \
  --hidden-import onnxruntime \
  --hidden-import tokenizers \
  --collect-all onnxruntime \
  --collect-all tokenizers \
  --hidden-import paceback_engine.resources \
  --add-data "${PROJECT_DIR}/engine/src/paceback_engine/resources/evidence_seed.json:paceback_engine/resources" \
  "${PYINSTALLER_SIGNING[@]}" \
  "${PROJECT_DIR}/engine/src/paceback_engine/cli.py"

ditto "${HELPER_BUILD}/dist/paceback-engine.app" \
  "${APP_DIR}/Contents/Helpers/PaceBackEngine.app"

if [[ ${SIGN_IDENTITY} == "-" ]]; then
  SIGN_FLAGS=(--force --sign - --timestamp=none)
else
  SIGN_FLAGS=(--force --sign "${SIGN_IDENTITY}" --options runtime --timestamp)
fi

# PyInstaller lays native dependencies in Frameworks and data in Resources, then
# signs the helper bundle. This canonical nested bundle avoids placing data next
# to an executable in Contents/Helpers, which strict code signing rejects.
codesign --verify --deep --strict --verbose=2 \
  "${APP_DIR}/Contents/Helpers/PaceBackEngine.app"
codesign "${SIGN_FLAGS[@]}" "${APP_DIR}/Contents/MacOS/PaceBack"
codesign "${SIGN_FLAGS[@]}" --entitlements "${PROJECT_DIR}/packaging/PaceBack.entitlements" \
  "${APP_DIR}"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}"

if [[ -d ${PROJECT_DIR}/output/pdf ]]; then
  rm -rf "${DEMO_PLAN_DIR}"
  ditto "${PROJECT_DIR}/output/pdf" "${DEMO_PLAN_DIR}"
fi

if [[ -n ${NOTARY_PROFILE:-} && ${SIGN_IDENTITY} != "-" ]]; then
  ARCHIVE=${OUTPUT_DIR}/PaceBack-notarization.zip
  rm -f "${ARCHIVE}"
  ditto -c -k --keepParent "${APP_DIR}" "${ARCHIVE}"
  xcrun notarytool submit "${ARCHIVE}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${APP_DIR}"
  spctl --assess --type execute --verbose=4 "${APP_DIR}"
fi

print "Built ${APP_DIR}"
