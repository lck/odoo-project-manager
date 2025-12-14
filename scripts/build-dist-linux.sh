#!/usr/bin/env bash
set -euo pipefail

# Native Linux single-file build for ./opm.py using PyInstaller
# Venv is created via uv. Output dir: ./opm-dist-linux
# Previous artifacts in output dir are deleted on each run.

DEFAULT_OUTPUT_DIR="$PWD/opm-dist-linux"
DEFAULT_PYTHON_MAJOR_MINOR="3.12"

usage() {
  cat <<'USAGE'
Usage:
  ./build-dist-linux.sh [--output DIR] [--python 3.12]

Options:
  --output DIR      Output directory (default: ./opm-dist-linux)
  --python X.Y      Python version for uv venv (default: 3.12)
  -h, --help        Show this help

Notes:
  - Run from repo root (must contain ./opm.py)
  - Requires: uv
  - Installs ONLY PyInstaller into the venv (no requirements.txt, no pyproject.toml install)
USAGE
}

OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
PYVER="$DEFAULT_PYTHON_MAJOR_MINOR"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_DIR="${2:-}"; shift 2;;
    --python) PYVER="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2;;
  esac
done

OPM_PY="$PWD/opm.py"
if [[ ! -f "$OPM_PY" ]]; then
  echo "ERROR: ./opm.py not found. Run this script from the repository root." >&2
  exit 1
fi

command -v uv >/dev/null 2>&1 || { echo "ERROR: uv not found in PATH." >&2; exit 1; }

# Read version from opm.py: __version__ = "x.y.z"
VERSION="$(
  sed -nE "s/^__version__[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/p" "$OPM_PY" | head -n 1
)"
if [[ -z "$VERSION" ]]; then
  echo "ERROR: Could not parse __version__ from $OPM_PY" >&2
  exit 1
fi

OUT_BIN_NAME="opm"
OUT_BIN_PATH="$OUTPUT_DIR/$OUT_BIN_NAME"

README_MD="$PWD/README.md"
README_HTML="$OUTPUT_DIR/README.html"

VENV_DIR="$OUTPUT_DIR/venv"
PYI_DIR="$OUTPUT_DIR/pyinstaller"
PYI_DIST="$PYI_DIR/dist"
PYI_BUILD="$PYI_DIR/build"
PYI_SPEC="$PYI_DIR/spec"

echo "==> Cleaning previous artifacts in $OUTPUT_DIR ..."
rm -rf "$VENV_DIR" "$PYI_DIR" 2>/dev/null || true
rm -f "$OUT_BIN_PATH" 2>/dev/null || true
rm -f "$README_HTML" 2>/dev/null || true

mkdir -p "$OUTPUT_DIR" "$PYI_DIST" "$PYI_BUILD" "$PYI_SPEC"

echo "==> Output dir:     $OUTPUT_DIR"
echo "==> Python version: $PYVER"
echo "==> OPM version:    $VERSION"
echo "==> Output binary:  $OUT_BIN_NAME"
echo

echo "==> (1) Creating venv via uv..."
uv venv -p "$PYVER" "$VENV_DIR"

PYTHON_EXE="$VENV_DIR/bin/python"

echo "==> (2) Installing ONLY PyInstaller..."
uv pip install -p "$PYTHON_EXE" pyinstaller

echo "==> (3) Building Linux binary with PyInstaller..."
"$VENV_DIR/bin/pyinstaller" \
  -F "$OPM_PY" \
  --clean \
  --distpath "$PYI_DIST" \
  --workpath "$PYI_BUILD" \
  --specpath "$PYI_SPEC"

if [[ ! -f "$PYI_DIST/$OUT_BIN_NAME" ]]; then
  echo "ERROR: Build finished but $PYI_DIST/$OUT_BIN_NAME not found." >&2
  exit 1
fi

echo "==> Copying result to output directory..."
cp -f "$PYI_DIST/$OUT_BIN_NAME" "$OUT_BIN_PATH"
chmod +x "$OUT_BIN_PATH" || true

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
echo "DONE: Built: $OUT_BIN_PATH"
