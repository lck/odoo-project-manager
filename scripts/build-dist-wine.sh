#!/usr/bin/env bash
set -euo pipefail

# Build opm.exe under Wine.
# Keeps Wine prefix and generated files after build.
# On the NEXT run, it deletes the previous generated artifacts first.
# All artifacts are stored under the output directory. "Wine-native" artifacts live inside the Wine prefix.

DEFAULT_OUTPUT_DIR="$PWD/opm-dist-wine"
DEFAULT_PYTHON_MAJOR_MINOR="3.12"

usage() {
  cat <<'USAGE'
Usage:
  ./build-dist-wine.sh [--output DIR] [--prefix PATH] [--python 3.12]

Options:
  --output DIR      Main output directory (default: ./opm-dist-wine)
  --prefix PATH     Wine prefix directory to use (default: <output>/wine)
  --python X.Y      Python version to install via uv inside Wine (default: 3.12)
  -h, --help        Show this help

Notes:
  - Run this from the repository root (must contain ./opm.py).
  - Requires: wine (64-bit), curl, unzip.
  - Artifacts are kept after build, and are deleted on the next run (within the output directory).
USAGE
}

PREFIX=""
OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
PYVER="$DEFAULT_PYTHON_MAJOR_MINOR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_DIR="${2:-}"; shift 2;;
    --prefix)
      PREFIX="${2:-}"; shift 2;;
    --python)
      PYVER="${2:-}"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2;;
  esac
done

mkdir -p "$OUTPUT_DIR"

# If prefix not provided, default to: <output>/wine
if [[ -z "$PREFIX" ]]; then
  PREFIX="$OUTPUT_DIR/wine"
fi

# Basic validation
OPM_PY="$PWD/opm.py"
if [[ ! -f "$OPM_PY" ]]; then
  echo "ERROR: ./opm.py not found. Run this script from the repository root." >&2
  exit 1
fi

command -v wine >/dev/null 2>&1 || { echo "ERROR: wine not found in PATH." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found in PATH." >&2; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo "ERROR: unzip not found in PATH." >&2; exit 1; }

# Parse version from opm.py: __version__ = "0.1.1" (supports both quote styles)
VERSION="$(
  sed -nE "s/^__version__[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$OPM_PY" | head -n 1
)"
if [[ -z "$VERSION" ]]; then
  echo "ERROR: Could not parse __version__ from $OPM_PY" >&2
  exit 1
fi

#OUT_EXE_NAME="opm-${VERSION}.exe"
OUT_EXE_NAME="opm.exe"
OUT_EXE_PATH="$OUTPUT_DIR/$OUT_EXE_NAME"

README_MD="$PWD/README.md"
README_HTML="$OUTPUT_DIR/README.html"

# Host-side directories under OUTPUT_DIR
REQ_DIR="$OUTPUT_DIR/requirements"
TMP_DIR="$OUTPUT_DIR/tmp"
XDG_CACHE="$TMP_DIR/xdg-cache"
XDG_DATA="$TMP_DIR/xdg-data"
UV_CACHE="$TMP_DIR/uv-cache"

UV_ZIP="$REQ_DIR/uv-x86_64-pc-windows-msvc.zip"
UV_URL="https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip"

mkdir -p "$REQ_DIR" "$TMP_DIR" "$XDG_CACHE" "$XDG_DATA" "$UV_CACHE"

# Wine-native workspace inside the prefix
WIN_WORK_DIR="$PREFIX/drive_c/opm-build"
WIN_TOOLS_DIR="$WIN_WORK_DIR/tools"
WIN_VENV_DIR="$WIN_WORK_DIR/venv"
WIN_PYI_DIR="$WIN_WORK_DIR/pyinstaller"
WIN_PYI_DIST="$WIN_PYI_DIR/dist"
WIN_PYI_BUILD="$WIN_PYI_DIR/build"
WIN_PYI_SPEC="$WIN_PYI_DIR/spec"
WIN_UV_EXE="$WIN_TOOLS_DIR/uv.exe"

# Clean previous run artifacts (within OUTPUT_DIR only)
cleanup_previous() {
  echo "==> Cleaning artifacts from previous run (within $OUTPUT_DIR)..."

  # Remove the prefix entirely (it is under OUTPUT_DIR by default; if overridden, still remove that chosen path)
  rm -rf "$PREFIX" 2>/dev/null || true

  # Remove host-side artifacts under OUTPUT_DIR
  rm -rf "$TMP_DIR" "$XDG_CACHE" "$XDG_DATA" "$UV_CACHE" 2>/dev/null || true
  rm -rf "$REQ_DIR" 2>/dev/null || true
  rm -f "$OUTPUT_DIR"/opm-*.exe 2>/dev/null || true
  rm -f "$README_HTML" 2>/dev/null || true

  mkdir -p "$REQ_DIR" "$TMP_DIR" "$XDG_CACHE" "$XDG_DATA" "$UV_CACHE"

  echo "==> Cleanup done."
  echo
}

cleanup_previous

# Keep caches under OUTPUT_DIR
export TMPDIR="$TMP_DIR"
export XDG_CACHE_HOME="$XDG_CACHE"
export XDG_DATA_HOME="$XDG_DATA"
export UV_CACHE_DIR="$UV_CACHE"

export WINEPREFIX="$PREFIX"
export WINEARCH="win64"

# Disable Wine Mono/.NET and Gecko prompts (we don't need .NET/embedded HTML)
export WINEDLLOVERRIDES="mscoree=d;mshtml=d"

echo "==> Using WINEPREFIX: $WINEPREFIX"
echo "==> Output dir:       $OUTPUT_DIR"
echo "==> Python version:   $PYVER"
echo "==> OPM version:      $VERSION"
echo "==> Output exe:       $OUT_EXE_NAME"
echo

echo "==> (1) Initializing 64-bit Wine prefix..."
wineboot -u >/dev/null 2>&1 || wineboot -u

echo "==> (2) Downloading uv (Windows)..."
curl -L --fail -o "$UV_ZIP" "$UV_URL"

# Prepare Wine-native directories
mkdir -p "$WIN_TOOLS_DIR" "$WIN_PYI_DIST" "$WIN_PYI_BUILD" "$WIN_PYI_SPEC"

# Extract uv.exe and place it inside the prefix (Wine-native)
extract_dir="$(mktemp -d "$TMP_DIR/uv-extract-XXXXXX")"
unzip -o "$UV_ZIP" -d "$extract_dir" >/dev/null
uv_path="$(find "$extract_dir" -type f -iname "uv.exe" | head -n 1 || true)"
if [[ -z "$uv_path" ]]; then
  echo "ERROR: uv.exe not found in downloaded zip." >&2
  exit 1
fi
cp -f "$uv_path" "$WIN_UV_EXE"
rm -rf "$extract_dir"

if [[ ! -f "$WIN_UV_EXE" ]]; then
  echo "ERROR: uv.exe missing after extraction/copy." >&2
  exit 1
fi

echo "==> (3) Installing CPython ${PYVER} (x64) inside Wine via uv..."
CPY_TAG="cpython-${PYVER}-windows-x86_64-none"
wine "$WIN_UV_EXE" python install "$CPY_TAG"

echo "==> (4) Building opm.exe with PyInstaller..."
wine "$WIN_UV_EXE" venv -p "$PYVER" "$WIN_VENV_DIR"
wine "$WIN_UV_EXE" pip install -p "$WIN_VENV_DIR/Scripts/python.exe" pyinstaller

# Produce all PyInstaller outputs under the prefix (Wine-native)
wine "$WIN_VENV_DIR/Scripts/pyinstaller.exe" \
  -F "$OPM_PY" \
  --clean \
  --distpath "$WIN_PYI_DIST" \
  --workpath "$WIN_PYI_BUILD" \
  --specpath "$WIN_PYI_SPEC"

if [[ ! -f "$WIN_PYI_DIST/opm.exe" ]]; then
  echo "ERROR: Build finished but $WIN_PYI_DIST/opm.exe not found." >&2
  exit 1
fi

echo "==> Copying result to output directory..."
cp -f "$WIN_PYI_DIST/opm.exe" "$OUT_EXE_PATH"

echo "==> Generating README.html via pandoc..."
if command -v pandoc >/dev/null 2>&1; then
  if [[ -f "$README_MD" ]]; then
    pandoc "$README_MD" -o "$README_HTML" --standalone -V maxwidth=60em
  else
    echo "WARNING: $README_MD not found, skipping README.html generation." >&2
  fi
else
  echo "WARNING: pandoc not found in PATH, skipping README.html generation." >&2
fi

echo
echo "DONE: Built: $OUT_EXE_PATH"
echo "INFO: Wine prefix and Wine-native artifacts kept under: $PREFIX"
echo "INFO: They will be deleted on the next run."
