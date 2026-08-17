#!/usr/bin/env bash
# update.sh — Pin mesa-git-nix to the latest Mesa main branch commit.
#
# Follows the Daaboulex Nix Packaging Standard update contract:
#   Exit 0: no update needed, or update succeeded (check 'updated' output)
#   Exit 1: update found but verification failed
#   Exit 2: network/API error
#
# Outputs (via GITHUB_OUTPUT): updated, new_version, old_version, package_name,
#   error_type, upstream_url

set -euo pipefail

REPO_URL="https://gitlab.freedesktop.org/mesa/mesa.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_FILE="${GITHUB_OUTPUT:-/tmp/update-outputs.env}"
: >"$OUTPUT_FILE"

output() { echo "$1=$2" >>"$OUTPUT_FILE"; }
log() { echo "==> $*"; }
err() { echo "::error::$*"; }

# Diagnostics go to stderr: stdout carries the hash to the caller's $(...).
prefetch_hash() {
  local url=$1 errfile out hash
  errfile=$(mktemp)
  out=$(nix store prefetch-file --unpack --json "$url" 2>"$errfile")
  hash=$(jq -r '.hash // empty' <<<"$out" 2>/dev/null)
  if [ -z "$hash" ]; then
    {
      echo "::error::prefetch failed for $url"
      grep -oiE 'HTTP error [0-9]{3}|Too Many Requests|error: .*' "$errfile" |
        sort -u | head -3 | sed 's/^/::error::  /'
    } >&2
    rm -f "$errfile"
    return 1
  fi
  rm -f "$errfile"
  printf '%s' "$hash"
}

output "package_name" "mesa-git"
output "upstream_url" "$REPO_URL"

[ -r "$REPO_ROOT/version.json" ] || {
  err "version.json not readable at $REPO_ROOT -- repo layout drifted from this script"
  output "error_type" "layout"
  output "updated" "false"
  exit 1
}

# --- Read current state ---
CURRENT_REV=$(jq -r '.rev' "$REPO_ROOT/version.json")
CURRENT_VERSION=$(jq -r '.version' "$REPO_ROOT/version.json")
output "old_version" "$CURRENT_REV"
log "Current rev: ${CURRENT_REV:0:12}"

# --- Fetch latest commit ---
log "Fetching latest Mesa main commit..."
REV=$(git ls-remote "$REPO_URL" refs/heads/main | cut -f1) || {
  log "Network error fetching Mesa main"
  output "updated" "false"
  exit 2
}
if [ -z "$REV" ]; then
  log "Empty rev from ls-remote"
  output "updated" "false"
  exit 2
fi
log "Latest rev: ${REV:0:12}"
output "new_version" "$REV"

# --- Compare ---
if [ "$CURRENT_REV" = "$REV" ]; then
  log "Already up to date"
  output "updated" "false"
  exit 0
fi
log "Update found: ${CURRENT_REV:0:12} → ${REV:0:12}"
output "updated" "true"

# --- Compute source hash ---
log "Computing source hash..."
ARCHIVE_URL="https://gitlab.freedesktop.org/mesa/mesa/-/archive/${REV}/mesa-${REV}.tar.gz"
HASH=$(prefetch_hash "$ARCHIVE_URL") || {
  output "error_type" "hash-extraction"
  exit 1
}
DATE=$(date -u +%Y-%m-%d)
log "Hash: $HASH"
log "Date: $DATE"

# --- Extract version string ---
log "Extracting Mesa version string..."
VERSION_STRING="$CURRENT_VERSION"
# Mesa uses a VERSION file (or inline in meson.build for older commits)
VERSION_URL="https://gitlab.freedesktop.org/mesa/mesa/-/raw/${REV}/VERSION"
MESA_VERSION=$(curl -sfL "$VERSION_URL" | head -1 | tr -d '[:space:]') || true
if [ -z "$MESA_VERSION" ]; then
  # Fallback: inline version in meson.build project() declaration
  MESON_URL="https://gitlab.freedesktop.org/mesa/mesa/-/raw/${REV}/meson.build"
  MESA_VERSION=$(curl -sfL "$MESON_URL" | head -10 | grep -oP "version\s*:\s*'\K[^']+" | head -1) || true
fi
if [ -n "$MESA_VERSION" ]; then
  VERSION_STRING="${MESA_VERSION}"
  log "Mesa version: $VERSION_STRING"
fi

# --- Update version.json ---
log "Updating version.json..."
cat >"$REPO_ROOT/version.json" <<EOF
{
    "rev": "$REV",
    "hash": "$HASH",
    "version": "$VERSION_STRING",
    "date": "$DATE"
}
EOF

# --- Regenerate wraps.json (Rust crate dependencies) ---
log "Fetching subprojects/*.wrap for Rust crate deps..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"
git init -q
git remote add origin "$REPO_URL"
git fetch --depth 1 origin "$REV" 2>&1 | tail -1
git checkout FETCH_HEAD -- subprojects/ 2>/dev/null

log "Generating wraps.json..."
python3 <<'PYEOF'
import configparser, pathlib, json, base64, binascii, urllib.parse

def to_sri(h):
    raw = binascii.unhexlify(h)
    b64 = base64.b64encode(raw).decode()
    return f"sha256-{b64}"

result = []
for f in sorted(pathlib.Path("subprojects").glob("*.wrap")):
    p = configparser.ConfigParser()
    p.read(f)
    if "wrap-file" not in p.sections():
        continue
    url = p.get("wrap-file", "source_url", fallback="")
    if "crates.io" not in url:
        continue
    parsed = urllib.parse.urlparse(url)
    parts = parsed.path.strip("/").split("/")
    ci = parts.index("crates")
    name = parts[ci + 1]
    version = parts[ci + 2]
    h = p.get("wrap-file", "source_hash")
    result.append({"pname": name, "version": version, "hash": to_sri(h)})

with open("wraps_out.json", "w") as fd:
    json.dump(result, fd, indent=4)
    fd.write("\n")
PYEOF

cp wraps_out.json "$REPO_ROOT/wraps.json"

# --- Pin for overlays/venus-protocol.nix (lifecycle tied to that fix file) ---
if [ ! -f "$REPO_ROOT/overlays/venus-protocol.nix" ]; then
  rm -f "$REPO_ROOT/venus-protocol.json"
elif [ -f subprojects/venus-protocol.wrap ]; then
  VP_REV=$(grep -E '^revision' subprojects/venus-protocol.wrap | sed 's/.*= *//' | tr -d '[:space:]')
  VP_DIR=$(grep -E '^directory' subprojects/venus-protocol.wrap | sed 's/.*= *//' | tr -d '[:space:]')
  if [ -z "$VP_REV" ] || [ -z "$VP_DIR" ]; then
    err "venus-protocol.wrap present but revision/directory unparsable"
    output "error_type" "wrap-parse"
    exit 1
  fi
  VP_URL="https://gitlab.freedesktop.org/virgl/venus-protocol/-/archive/${VP_REV}/venus-protocol-${VP_REV}.tar.gz"
  VP_HASH=$(prefetch_hash "$VP_URL") || {
    output "error_type" "hash-extraction"
    exit 1
  }
  log "venus-protocol: ${VP_REV:0:12} (${VP_DIR})"
  cat >"$REPO_ROOT/venus-protocol.json" <<EOF
{
    "rev": "$VP_REV",
    "hash": "$VP_HASH",
    "directory": "$VP_DIR"
}
EOF
else
  log "mesa no longer carries venus-protocol.wrap; keeping the last pin until heal-overlays retires the fix"
fi

cd "$REPO_ROOT"

SHORT_REV="${REV:0:12}"

# --- Verification ---
log "Running verification chain..."

log "Step 1/2: nix flake check --no-build"
if ! nix flake check --no-build 2>&1; then
  err "Eval check failed"
  output "error_type" "eval-error"
  exit 1
fi

log "Step 2/2: nix eval version"
BUILT_VERSION=$(nix eval --raw .#mesa-git.version 2>&1) || {
  err "Version eval failed"
  output "error_type" "eval-error"
  exit 1
}
log "Built version: $BUILT_VERSION"

log "Update verified: ${CURRENT_REV:0:12} → ${SHORT_REV}"
exit 0
