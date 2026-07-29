#!/usr/bin/env bash
# check-version-sync.sh — verify every version-bearing file in the repo agrees.
#
# Canonical fleet copy. Derived from yarr's variant, with the hardcoded
# packages/<name>/package.json generalized to a glob so one script works in
# every repo. Exits non-zero when versions disagree.
#
# Usage: check-version-sync.sh [PROJECT_DIR]
set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

versions=()
files_checked=()

add_json_version() { # path
  [ -f "$1" ] || return 0
  local v
  v=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version',''))" "$1" 2>/dev/null) || return 0
  [ -n "$v" ] && versions+=("$1=$v") && files_checked+=("$1")
  return 0
}

add_toml_version() { # path
  [ -f "$1" ] || return 0
  local v
  v=$(grep -m1 '^version' "$1" | sed 's/.*"\(.*\)".*/\1/')
  [ -n "$v" ] && versions+=("$1=$v") && files_checked+=("$1")
  return 0
}

add_toml_version "Cargo.toml"
add_toml_version "pyproject.toml"
add_json_version "package.json"

# Every npm workspace member, rather than one hardcoded path.
for pkg in packages/*/package.json; do
  [ -e "$pkg" ] && add_json_version "$pkg"
done

add_json_version ".claude-plugin/plugin.json"
add_json_version ".codex-plugin/plugin.json"
add_json_version "gemini-extension.json"
add_json_version "mcpb/manifest.json"

# server.json carries the version in several places: top level, each entry in
# packages[], the publisher-provided buildInfo, and the composite
# distribution.npm ("<name>@<version>"). Check them all — a partial check is
# what let one repo sit seven releases out of sync while reporting OK.
if [ -f "server.json" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && versions+=("$line")
  done < <(python3 - <<'PY'
import json, re
try:
    d = json.load(open("server.json"))
except Exception:
    raise SystemExit(0)
if d.get("version"):
    print(f"server.json version={d['version']}")
for i, p in enumerate(d.get("packages") or []):
    if p.get("version"):
        print(f"server.json packages[{i}].version={p['version']}")
meta = (d.get("_meta") or {}).get("io.modelcontextprotocol.registry/publisher-provided") or {}
bi = meta.get("buildInfo") or {}
if bi.get("version"):
    print(f"server.json buildInfo.version={bi['version']}")
npm = (meta.get("distribution") or {}).get("npm")
if npm and "@" in npm:
    print(f"server.json distribution.npm={npm.rsplit('@', 1)[1]}")
PY
)
  files_checked+=("server.json")
fi

if [ ${#versions[@]} -eq 0 ]; then
  echo "[version-sync] No version-bearing files found — skipping"
  exit 0
fi

canonical=""
mismatch=0
for entry in "${versions[@]}"; do
  ver="${entry##*=}"
  if [ -z "$canonical" ]; then
    canonical="$ver"
  elif [ "$ver" != "$canonical" ]; then
    mismatch=1
  fi
done

if [ "$mismatch" -eq 1 ]; then
  echo "[version-sync] FAIL — versions are out of sync:"
  for entry in "${versions[@]}"; do
    file="${entry%%=*}"
    ver="${entry##*=}"
    marker=" "
    [ "$ver" != "$canonical" ] && marker="!"
    echo "  $marker $file: $ver"
  done
  echo ""
  echo "All version-bearing files must have the same version."
  echo "Files checked: ${files_checked[*]}"
  exit 1
fi

if [ -f "CHANGELOG.md" ]; then
  if ! grep -qF "$canonical" CHANGELOG.md; then
    echo "[version-sync] WARN — CHANGELOG.md has no entry for version $canonical"
  fi
fi

echo "[version-sync] OK — all ${#versions[@]} version fields at v${canonical}"
exit 0
