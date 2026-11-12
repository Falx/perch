#!/usr/bin/env bash
#
# Validate and package Perch.
#
#   tools/package.sh
#
# Checks: Lua syntax, TOC/file consistency, stray files.
# Output: dist/Perch-<version>.zip  (root folder is Perch/)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ADDON="Perch"
TOC="$ADDON/Perch.toc"

fail() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "== $*"; }

[ -f "$TOC" ] || fail "missing $TOC"

VERSION="$(sed -n 's/^##[[:space:]]*Version:[[:space:]]*//p' "$TOC" | head -1 | tr -d '\r')"
[ -n "$VERSION" ] || fail "no '## Version:' entry in $TOC"

BUILD="dev"
if git rev-parse --git-dir > /dev/null 2>&1; then
  BUILD="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    BUILD="${BUILD}-dirty"
  fi
fi

echo "Perch $VERSION (build $BUILD)"

step "Lua syntax"
while IFS= read -r -d '' file; do
  luajit -bl "$file" > /dev/null 2>&1 || fail "syntax error: $file"
done < <(find "$ADDON" -name '*.lua' -print0)
echo "  ok"

step "TOC consistency"
mapfile -t LISTED < <(grep -v '^#' "$TOC" | tr -d '\r' | sed '/^[[:space:]]*$/d' | sed 's/[[:space:]]*$//')
for entry in "${LISTED[@]}"; do
  path="$ADDON/${entry//\\//}"
  [ -f "$path" ] || fail "TOC lists a missing file: $entry"
done
while IFS= read -r file; do
  relative="${file#"$ADDON"/}"
  found=0
  for entry in "${LISTED[@]}"; do
    if [ "${entry//\\//}" = "$relative" ]; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ] || fail "file not listed in TOC: $relative"
done < <(find "$ADDON" -name '*.lua' | sort)
echo "  ok (${#LISTED[@]} files)"

step "Stray files"
STRAY="$(find "$ADDON" \( -name '.DS_Store' -o -name '*~' -o -name '*.orig' -o -name '*.bak' -o -name '*.swp' -o -name '*.tmp' \) -print)"
[ -z "$STRAY" ] || fail "remove stray files: $STRAY"
echo "  ok"

step "Package"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$ADDON"
cp -R "$ADDON/." "$STAGE/$ADDON/"

sed -i "s/^P\.build = \"dev\"/P.build = \"$BUILD\"/" "$STAGE/$ADDON/Core.lua"
grep -q "P\.build = \"$BUILD\"" "$STAGE/$ADDON/Core.lua" \
  || fail "could not inject the build stamp into Core.lua"

mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/$ADDON-$VERSION.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -qr "$ZIP" "$ADDON" )

echo "  $ZIP"
unzip -l "$ZIP" | sed -n '4,$p'

echo
echo "done."
