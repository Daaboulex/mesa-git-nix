# This file documents the mesa-git package for reference.
# The actual package is produced by the overlay (overlay.nix) via overrideAttrs
# on nixpkgs' mesa derivation. This avoids duplicating mesa's complex ~400-line
# derivation and automatically inherits all build inputs, meson flags, and
# post-processing from upstream nixpkgs.
#
# Key differences from nixpkgs mesa:
#   - Source: pinned git main commit (version.json) instead of release tarball
#   - Patches: nixpkgs' opencl.patch dropped; equivalent changes applied via postPatch
#   - Wraps: updated Rust crate deps (wraps.json) matching git main's subprojects/
#   - mesa-gl-headers check: skipped (git headers won't match pinned release headers)
#
# To update: run ./update.sh to fetch the latest mesa main commit and regenerate
# version.json + wraps.json.
{ }
