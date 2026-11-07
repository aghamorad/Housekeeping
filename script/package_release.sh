#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
if [[ -d "${XCODE_APP:-/Applications/Xcode.app}" ]]; then
  XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
elif [[ -d "/Applications/Xcode-beta.app" ]]; then
  XCODE_APP="/Applications/Xcode-beta.app"
else
  echo "Housekeeping packaging requires Xcode.app or Xcode-beta.app in /Applications." >&2
  exit 1
fi
SWIFTC="$XCODE_APP/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$XCODE_APP/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
APP_NAME="Housekeeping"
MIN_MACOS="13.0"

if [[ ! -x "$SWIFTC" || ! -d "$SDK" ]]; then
  echo "Housekeeping packaging could not find a usable macOS SDK and Swift compiler in $XCODE_APP." >&2
  exit 1
fi

# Every Swift file the app is made of, listed once. swiftc takes no project file
# here, so a source added to the Xcode project and forgotten in this list is a
# build failure at packaging time rather than at commit time — which is exactly
# how ProtectionList.swift went missing from this script.
SOURCES=(
  "$ROOT_DIR/Housekeeping/Sources/main.swift"
  "$ROOT_DIR/Housekeeping/Sources/AppDelegate.swift"
  "$ROOT_DIR/Housekeeping/Sources/AppState.swift"
  "$ROOT_DIR/Housekeeping/Sources/HousekeepingApp.swift"
  "$ROOT_DIR"/Housekeeping/Sources/Core/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/CLI/*.swift
  "$ROOT_DIR/Housekeeping/Sources/Scanner/ScanModels.swift"
  "$ROOT_DIR/Housekeeping/Sources/Scanner/BoundedScanner.swift"
  "$ROOT_DIR/Housekeeping/Sources/Scanner/OfficeAddInAudit.swift"
  "$ROOT_DIR"/Housekeeping/Sources/Classifier/*.swift
  "$ROOT_DIR/Housekeeping/Sources/Cleanup/CleanupModels.swift"
  "$ROOT_DIR/Housekeeping/Sources/Cleanup/SafetyPolicy.swift"
  "$ROOT_DIR/Housekeeping/Sources/Cleanup/ProtectionList.swift"
  "$ROOT_DIR/Housekeeping/Sources/Cleanup/SafeCleanupEngine.swift"
  "$ROOT_DIR/Housekeeping/Sources/Cleanup/ProtectedDataPolicy.swift"
  "$ROOT_DIR"/Housekeeping/Sources/Cleaner/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Hardware/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Disk/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Reconcile/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Update/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/SelfUpdate/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Environment/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/AppRepair/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/UI/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/MenuBar/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Housekeeper/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Routes/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Network/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Phone/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/MediaDock/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Bookbind/*.swift
  "$ROOT_DIR"/Housekeeping/Sources/Models/*.swift
)

WORK_ROOT="$(mktemp -d /private/tmp/housekeeping-package.XXXXXX)"
cleanup() {
  # Preserve generated work for recovery rather than recursively deleting it.
  if [[ -d "$WORK_ROOT" ]]; then
    mv "$WORK_ROOT" "$HOME/.Trash/$(basename "$WORK_ROOT")"
  fi
}
trap cleanup EXIT

UNIVERSAL_APP="$OUTPUT_DIR/$APP_NAME.app"
UNIVERSAL_ZIP="$OUTPUT_DIR/$APP_NAME-macOS-universal.zip"

for existing in "$UNIVERSAL_APP" "$UNIVERSAL_ZIP"; do
  if [[ -e "$existing" ]]; then
    echo "Safety stop: $existing already exists." >&2
    exit 1
  fi
done

# The housekeeper's runtime, built from source by Tools/llama-static/build.sh.
# It is deliberately not in the repository — 38 MB that every clone would carry
# forever, for a file three scripted steps can rebuild — so a fresh checkout has
# to be pointed at a copy. Missing, this stops the release rather than shipping
# an app whose housekeeper silently never wakes up.
RUNTIME="$ROOT_DIR/Housekeeping/Resources/llama-server"
if [[ ! -x "$RUNTIME" ]]; then
  echo "Safety stop: $RUNTIME is missing." >&2
  echo "Build it with Tools/llama-static/build.sh and copy the result there." >&2
  exit 1
fi

# A universal entry point is insufficient: every frozen Python extension and
# media executable must also run on either Mac, without Homebrew or user Python.
BOOKBIND_SRC="$ROOT_DIR/Runtime/Bookbind"
BOOKBIND_BIN="${HOUSEKEEPING_BOOKBIND_BIN:-$ROOT_DIR/.build/bookbind-universal/bin}"
for tool in BookbindServer ffmpeg ffprobe; do
  [[ -x "$BOOKBIND_BIN/$tool" ]] || { echo "Missing universal $tool; run script/build_bookbind_runtime.sh." >&2; exit 1; }
done
[[ -d "$BOOKBIND_BIN/_internal" && -f "$BOOKBIND_SRC/app.py" ]] || { echo "Bookbind's complete runtime/source is missing." >&2; exit 1; }
python3 "$ROOT_DIR/script/verify_universal_bundle.py" "$RUNTIME" "$BOOKBIND_BIN"
python3 "$ROOT_DIR/script/bookbind_runtime_manifest.py" verify "$BOOKBIND_SRC" "$BOOKBIND_BIN/runtime-manifest.json"

compile() {
  local arch="$1"
  local output="$2"
  "$SWIFTC" \
    -O \
    -whole-module-optimization \
    -warnings-as-errors \
    -sdk "$SDK" \
    -target "$arch-apple-macosx$MIN_MACOS" \
    -module-cache-path "$WORK_ROOT/ModuleCache" \
    -o "$output" \
    "${SOURCES[@]}"
}

stage() {
  local binary="$1"
  local runtime="$2"
  local app="$3"
  [[ ! -e "$app" ]] || { echo "Safety stop: staging bundle already exists: $app" >&2; exit 1; }
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Rules"
  cp "$binary" "$app/Contents/MacOS/$APP_NAME"
  cp "$ROOT_DIR/Housekeeping/Info.plist" "$app/Contents/Info.plist"

  # The staged copy records the commit it was built from, so the app can ask a
  # newer copy of itself to do the same and compare the two. Stamped into the
  # copy, never into the source Info.plist: that file is tracked, and a build
  # that rewrote it would leave every source folder permanently dirty — which is
  # precisely the condition the self-update refuses to run in.
  local plist="$app/Contents/Info.plist"
  local commit branch built base_commit source_digest
  commit="$(/usr/bin/git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || true)"
  base_commit="$commit"
  # A local edit is not the recorded commit. Preserve the base and fingerprint
  # the actual inputs, while leaving SourceCommit absent so the updater cannot
  # claim that this modified app is identical to the published revision.
  if [[ -n "$(/usr/bin/git -C "$ROOT_DIR" status --porcelain -- Housekeeping Runtime script)" ]]; then
    commit=""
  fi
  source_digest="$(shasum -a 256 "${SOURCES[@]}" "$ROOT_DIR/Housekeeping/Info.plist" | shasum -a 256 | awk '{print $1}')"
  branch="$(/usr/bin/git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  built="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  for pair in "HousekeepingSourceCommit:$commit" "HousekeepingSourceBaseCommit:$base_commit" "HousekeepingSourceDigest:$source_digest" "HousekeepingSourceBranch:$branch" "HousekeepingBuildDate:$built"; do
    key="${pair%%:*}"
    value="${pair#*:}"
    [[ -n "$value" ]] || continue
    /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  done
  cp "$ROOT_DIR/Housekeeping/Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
  ditto "$ROOT_DIR/Housekeeping/Resources/Rules" "$app/Contents/Resources/Rules"
  if [[ -d "$ROOT_DIR/Housekeeping/Resources/BenignMonster" ]]; then
    ditto "$ROOT_DIR/Housekeeping/Resources/BenignMonster" "$app/Contents/Resources/BenignMonster"
  fi

  # The housekeeper's runtime travels inside the bundle. It is a single static
  # binary that links nothing but system frameworks — which is the whole reason a
  # shared llama.cpp build was rejected, since that shape would mean signing a
  # pile of nested dylibs beside it. It is signed before the bundle so there is
  # exactly one signature covering it, and no ambiguity about which one counts.
  cp "$runtime" "$app/Contents/Resources/llama-server"
  chmod 755 "$app/Contents/Resources/llama-server"
  codesign --force --sign - "$app/Contents/Resources/llama-server"

  # Versioned source and an explicitly verified universal runtime travel together.
  local bookbind_dst="$app/Contents/Resources/Bookbind"
  ditto "$BOOKBIND_SRC" "$bookbind_dst"
  ditto "$BOOKBIND_BIN" "$bookbind_dst/bin"

  codesign --force --deep --sign - "$app"
  codesign --verify --deep --strict "$app"
  python3 "$ROOT_DIR/script/verify_universal_bundle.py" "$app"
}

echo "Compiling for Apple silicon (arm64)..."
compile arm64 "$WORK_ROOT/$APP_NAME-arm64"
echo "Compiling for Intel (x86_64)..."
compile x86_64 "$WORK_ROOT/$APP_NAME-x86_64"

lipo -create \
  "$WORK_ROOT/$APP_NAME-arm64" \
  "$WORK_ROOT/$APP_NAME-x86_64" \
  -output "$WORK_ROOT/$APP_NAME-universal"

mkdir -p "$OUTPUT_DIR" "$WORK_ROOT/stage-universal"

echo "Staging and signing..."

stage "$WORK_ROOT/$APP_NAME-universal" "$RUNTIME" "$WORK_ROOT/stage-universal/$APP_NAME.app"

# One complete download works on either architecture.
ditto "$WORK_ROOT/stage-universal/$APP_NAME.app" "$UNIVERSAL_APP"
ditto -c -k --sequesterRsrc --keepParent "$WORK_ROOT/stage-universal/$APP_NAME.app" "$UNIVERSAL_ZIP"

echo
lipo -info "$UNIVERSAL_APP/Contents/MacOS/$APP_NAME"
echo
shasum -a 256 "$UNIVERSAL_ZIP"
