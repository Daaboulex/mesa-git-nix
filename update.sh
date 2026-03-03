#!/usr/bin/env bash
# update.sh — Pin mesa-git-nix to the latest Mesa main branch commit.
#
# Usage: ./update.sh
#
# This script:
#   1. Fetches the latest commit from mesa's main branch
#   2. Computes the source hash via nix-prefetch-git
#   3. Sparse-checks out subprojects/*.wrap to regenerate wraps.json
#   4. Updates version.json with the new rev, hash, and date

set -euo pipefail

REPO_URL="https://gitlab.freedesktop.org/mesa/mesa.git"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Fetching latest Mesa main commit..."
REV=$(git ls-remote "$REPO_URL" refs/heads/main | cut -f1)
echo "    rev: $REV"

echo "==> Computing source hash..."
# Use nix store prefetch-file (works with Determinate Nix, unlike nix-prefetch-git)
ARCHIVE_URL="https://gitlab.freedesktop.org/mesa/mesa/-/archive/${REV}/mesa-${REV}.tar.gz"
HASH=$(nix store prefetch-file --unpack --json "$ARCHIVE_URL" | python3 -c "import sys,json; print(json.load(sys.stdin)['hash'])")
DATE=$(date -u +%Y-%m-%d)
echo "    hash: $HASH"
echo "    date: $DATE"

echo "==> Updating version.json..."
cat > "$SCRIPT_DIR/version.json" << EOF
{
    "rev": "$REV",
    "hash": "$HASH",
    "version": "26.1.0-dev",
    "date": "$DATE"
}
EOF

echo "==> Fetching subprojects/*.wrap for Rust crate deps..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cd "$TMPDIR"
git init -q
git remote add origin "$REPO_URL"
git fetch --depth 1 origin "$REV" 2>&1 | tail -1
git checkout FETCH_HEAD -- subprojects/ 2>/dev/null

echo "==> Generating wraps.json..."
python3 << 'PYEOF'
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
    name = parts[3]
    version = parts[4]
    h = p.get("wrap-file", "source_hash")
    result.append({"pname": name, "version": version, "hash": to_sri(h)})

with open("wraps_out.json", "w") as fd:
    json.dump(result, fd, indent=4)
    fd.write("\n")
PYEOF

cp wraps_out.json "$SCRIPT_DIR/wraps.json"

echo "==> Done! Updated to Mesa main @ ${REV:0:12}"
echo "    Run 'nix build .#mesa-git' to test the build."
