#!/usr/bin/env bash
set -euo pipefail

# Build entirely inside the project. No system Python installation is changed.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build/universal-runtimes"
OUTPUT="$ROOT/.build/bookbind-universal/bin"
PYTHON_ROOT="$WORK/frameworks/Python.framework/Versions/3.15"
MEDIA_ARM="${HOUSEKEEPING_MEDIA_ARM64_BIN:-$ROOT/../Bookbind/bin}"
[[ ! -e "$OUTPUT" ]] || { echo "Output already exists: $OUTPUT; preserve it before rebuilding." >&2; exit 1; }
mkdir -p "$WORK/downloads"

download() {
  local url="$1" path="$2" checksum="$3"
  if [[ ! -f "$path" ]]; then
    curl --fail --location --retry 2 --max-time 300 "$url" -o "$path"
  fi
  echo "$checksum  $path" | shasum -a 256 -c -
}

download https://www.python.org/ftp/python/3.15.2/python-3.15.2-macos11.pkg \
  "$WORK/downloads/python-3.15.2.pkg" 2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396
pkgutil --check-signature "$WORK/downloads/python-3.15.2.pkg"
if [[ ! -d "$WORK/python-pkg" ]]; then
  pkgutil --expand-full "$WORK/downloads/python-3.15.2.pkg" "$WORK/python-pkg"
fi
if [[ ! -d "$PYTHON_ROOT" ]]; then
  mkdir -p "$WORK/frameworks"
  ditto "$WORK/python-pkg/Python_Framework.pkg/Payload" "$WORK/frameworks/Python.framework"
fi
python3 "$ROOT/script/prepare_bookbind_python.py" "$PYTHON_ROOT"
export PYTHONHOME="$PYTHON_ROOT"
PYTHON="$PYTHON_ROOT/bin/python3.15"
"$PYTHON" -m ensurepip
"$PYTHON" -m pip install --disable-pip-version-check -r "$ROOT/script/bookbind-runtime-requirements.txt"

# Universal2 must be built as such, including Python and extension modules.
# Combining two already-frozen PyInstaller executables with lipo is insufficient.
"$PYTHON" -m PyInstaller --target-arch universal2 --onedir --name BookbindServer \
  --distpath "$WORK/frozen-final" --workpath "$WORK/pyinstaller-final" --specpath "$WORK" \
  --collect-submodules mutagen --collect-data certifi \
  --add-data "$ROOT/Runtime/Bookbind/static:static" "$ROOT/Runtime/Bookbind/app.py"

download https://evermeet.cx/ffmpeg/ffmpeg-9.0.zip \
  "$WORK/downloads/ffmpeg-9.0-intel.zip" b1bd0cbaa0c889a08589dc1d14e4a08eebf425b8726c31a7e270e08552d0f271
download https://evermeet.cx/ffmpeg/ffprobe-9.0.zip \
  "$WORK/downloads/ffprobe-9.0-intel.zip" 66a5102de63ce1c6a203d05a463ac836100eba9403d16968674366de17452da6
mkdir -p "$WORK/intel"
ditto -x -k "$WORK/downloads/ffmpeg-9.0-intel.zip" "$WORK/intel"
ditto -x -k "$WORK/downloads/ffprobe-9.0-intel.zip" "$WORK/intel"

# Preserve the known complete arm64 codec build, with exact input checksums.
echo "591260c945d0eef150e3bf82b0ef988bd36a9cecc18ff05d6679617159f0a95e  $MEDIA_ARM/ffmpeg" | shasum -a 256 -c -
echo "e11c17e8200b3ee4c4c186d245e2b4053f01d56957336c1817fca0b997469106  $MEDIA_ARM/ffprobe" | shasum -a 256 -c -
mkdir -p "$(dirname "$OUTPUT")"
ditto "$WORK/frozen-final/BookbindServer" "$OUTPUT"
for tool in ffmpeg ffprobe; do
  lipo -create "$MEDIA_ARM/$tool" "$WORK/intel/$tool" -output "$OUTPUT/$tool"
  chmod 755 "$OUTPUT/$tool"
  codesign --force --sign - "$OUTPUT/$tool"
done
mkdir -p "$OUTPUT/licenses"
cp "$PYTHON_ROOT/lib/python3.15/LICENSE.txt" "$OUTPUT/licenses/Python.txt"
cp "$PYTHON_ROOT/lib/python3.15/site-packages/mutagen-1.47.0.dist-info/COPYING" "$OUTPUT/licenses/Mutagen.txt"
cp "$PYTHON_ROOT/lib/python3.15/site-packages/certifi-2026.10.23.dist-info/licenses/LICENSE" "$OUTPUT/licenses/Certifi.txt"
ditto "$PYTHON_ROOT/lib/python3.15/site-packages/pyinstaller-6.22.3.dist-info/licenses" "$OUTPUT/licenses/PyInstaller"
"$OUTPUT/ffmpeg" -L > "$OUTPUT/licenses/FFmpeg.txt" 2>&1
cp "$ROOT/Runtime/README.md" "$OUTPUT/licenses/Runtime-sources.md"
python3 "$ROOT/script/bookbind_runtime_manifest.py" write "$ROOT/Runtime/Bookbind" "$OUTPUT/runtime-manifest.json"
python3 "$ROOT/script/verify_universal_bundle.py" "$OUTPUT"
echo "Universal Bookbind runtime ready: $OUTPUT"
