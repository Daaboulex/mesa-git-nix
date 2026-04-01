# mesa-git-nix

Bleeding-edge [Mesa](https://www.mesa3d.org/) from the `main` branch, packaged as a Nix flake.

Overrides nixpkgs' `mesa` via `overrideAttrs` — no derivation rewrite needed. Provides an overlay (`mesa-git` / `mesa-git-32`), vendor-aware driver presets, and a NixOS module to swap the system graphics driver in one line.

## Why?

nixpkgs-unstable tracks Mesa stable releases. Mesa `main` often contains unreleased driver optimizations weeks or months before a stable cut:

- **RDNA 4 / GFX12**: RadeonSI compute dispatch, buffer/image clears, shader improvements
- **RADV**: Vulkan driver fixes, new extensions, performance tuning
- **NVK / ANV / etc.**: Ongoing Vulkan and OpenGL improvements across all drivers

[Chaotic-Nyx](https://github.com/chaotic-cx/nyx) (the previous community mesa-git source) was archived in December 2025 with no maintained replacement.

## Pinned Commit

| Field   | Value |
|---------|-------|
| Branch  | `main` |
| Rev     | [`580381d9e7f5`](https://gitlab.freedesktop.org/mesa/mesa/-/commit/580381d9e7f5bb63cece6e582adb82e4659e4523) |
| Version | `26.1.0-devel` |
| Date    | 2026-04-01 |

Updated automatically every 12 hours by CI. See [`version.json`](./version.json) for the full commit SHA.

## Usage

### Flake Input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    mesa-git-nix = {
      url = "github:daaboulex/mesa-git-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### Option A: NixOS Module (Recommended)

The included NixOS module sets `hardware.graphics.package` and `hardware.graphics.package32` for you, with optional vendor-based driver selection.

```nix
# configuration.nix or host config
{ inputs, ... }: {
  imports = [ inputs.mesa-git-nix.nixosModules.default ];

  nixpkgs.overlays = [ inputs.mesa-git-nix.overlays.default ];

  mesa-git = {
    enable = true;
    drivers = [ "amd" ];  # Only compile AMD drivers (see Driver Presets below)
  };
}
```

### Option B: Overlay Only

If you manage `hardware.graphics.package` yourself or want to integrate mesa-git into your own module system:

```nix
{ inputs, pkgs, lib, ... }: {
  nixpkgs.overlays = [ inputs.mesa-git-nix.overlays.default ];

  # All drivers (default)
  hardware.graphics.package = lib.mkForce pkgs.mesa-git;
  hardware.graphics.package32 = lib.mkForce pkgs.mesa-git-32;

  # Or with vendor selection (AMD-only)
  hardware.graphics.package = lib.mkForce (pkgs.mkMesaGit { vendors = [ "amd" ]; });
  hardware.graphics.package32 = lib.mkForce (pkgs.mkMesaGit32 { vendors = [ "amd" ]; });
}
```

### Option C: Standalone Build

```bash
nix build github:daaboulex/mesa-git-nix
nix eval github:daaboulex/mesa-git-nix#mesa-git.version
```

## Driver Presets

By default, mesa-git builds **all** drivers (same as nixpkgs). Set `drivers` to only compile what your hardware needs — this dramatically reduces build time.

### Vendor Presets

| Vendor | `drivers` | Gallium | Vulkan |
|--------|-----------|---------|--------|
| AMD | `[ "amd" ]` | radeonsi, r600, r300 | RADV |
| Intel | `[ "intel" ]` | iris, crocus, i915 | ANV, HasVK |
| NVIDIA | `[ "nvidia" ]` | nouveau, tegra | NVK |
| All | `[ ]` (default) | all 24 drivers | all 14 drivers |

### Common Essentials (Always Included)

Regardless of vendor selection, these are always built:

- **Gallium**: llvmpipe (software fallback), softpipe, zink (OpenGL-over-Vulkan), virgl (VM)
- **Vulkan**: Lavapipe/swrast (software fallback), virtio (VM)

### Multi-GPU / Integrated Graphics

For systems with multiple GPUs (e.g., Intel iGPU + NVIDIA dGPU), list all vendors:

```nix
mesa-git.drivers = [ "intel" "nvidia" ];  # Builds Intel + NVIDIA + common essentials
```

### Custom Driver Lists

For full control, use `mkMesaGit` / `mkMesaGit32` directly:

```nix
hardware.graphics.package = lib.mkForce (pkgs.mkMesaGit {
  galliumDrivers = [ "radeonsi" "llvmpipe" "zink" ];
  vulkanDrivers = [ "amd" "swrast" ];
});
```

## How It Works

The overlay applies `overrideAttrs` to nixpkgs' `mesa` derivation, changing only what's necessary:

| Attribute | Change |
|-----------|--------|
| `version` | `26.1.0-dev-<short-rev>` |
| `src` | Pinned git main commit from `version.json` |
| `patches` | Cleared (nixpkgs patches target release line numbers) |
| `postPatch` | Replicates `opencl.patch` effects via `substituteInPlace` + `sed`; skips `mesa-gl-headers` validation |
| `mesonFlags` | Driver lists replaced when vendor presets are used |
| `env.MESON_PACKAGE_CACHE_DIR` | Rebuilt from `wraps.json` (Rust crate deps matching git main) |

Everything else (build inputs, outputs, `postInstall`, `postFixup`) is inherited from nixpkgs.

### What the `postPatch` Does

1. **`clang-libdir` meson option** — nixpkgs' `opencl.patch` adds a custom meson option so Nix can control the clang library search path. We replicate this with `substituteInPlace` on `meson.build` and append the option definition from `clang-libdir-option.meson`.
2. **Rusticl ICD install** — disables auto-installing the `.icd` file (nixpkgs reconstructs it with an absolute Nix store path in `postInstall`).
3. **`mesa-gl-headers` check** — skipped entirely, since git main headers diverge from the pinned release headers package.

## Updating

```bash
./update.sh
```

This script:

1. Fetches the latest commit SHA from `gitlab.freedesktop.org/mesa/mesa` `main`
2. Computes the source hash with `nix-prefetch-git`
3. Sparse-clones `subprojects/*.wrap` to regenerate `wraps.json` (Rust crate dependencies)
4. Writes `version.json`

After updating, test with:

```bash
nix build .#mesa-git
nix eval .#mesa-git.version
```

## Verification

After `nixos-rebuild switch`:

```bash
# OpenGL version should show the git version string
glxinfo | grep "OpenGL version"

# Vulkan driver info should show RADV with git version
vulkaninfo | grep driverInfo
```

## Repository Structure

```
mesa-git-nix/
├── flake.nix                   # Flake: overlay + NixOS module + packages
├── flake.lock
├── overlay.nix                 # Nixpkgs overlay: mesa-git, mkMesaGit, driver presets
├── module.nix                  # NixOS module: mesa-git.enable + drivers option
├── clang-libdir-option.meson   # Meson option snippet (avoids Nix string escaping)
├── version.json                # Pinned commit: rev, hash, version, date
├── wraps.json                  # Rust crate deps for MESON_PACKAGE_CACHE_DIR
├── update.sh                   # Script to pin latest mesa main commit
├── pkgs/
│   └── mesa-git.nix            # Package documentation (build via overlay)
├── LICENSE
└── README.md
```

## License

This packaging flake is [MIT](./LICENSE) licensed. Mesa itself is distributed under the [MIT license](https://docs.mesa3d.org/license.html).
