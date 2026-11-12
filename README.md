# mesa-git-nix

<!-- BEGIN generated:badges -->
[![CI](https://github.com/Daaboulex/mesa-git-nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Daaboulex/mesa-git-nix/actions/workflows/ci.yml)
[![NixOS unstable](https://img.shields.io/badge/NixOS-unstable-78C0E8?logo=nixos&logoColor=white)](https://nixos.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
<!-- END generated:badges -->

[Mesa](https://www.mesa3d.org/) from the `main` branch, packaged as a Nix flake.

Overrides nixpkgs' `mesa` via `overrideAttrs` — no derivation rewrite needed. Provides an overlay (`mesa-git` / `mesa-git-32`), vendor-aware driver presets, and a NixOS module to swap the system graphics driver in one line.

<!-- BEGIN generated:upstream -->
## Upstream

| | |
|---|---|
| **Project** | <https://gitlab.freedesktop.org/mesa/mesa> |
| **License** | MIT |
| **Tracked** | Git HEAD (main) |

<!-- END generated:upstream -->

## Why?

nixpkgs-unstable tracks Mesa stable releases. Mesa `main` often contains unreleased driver optimizations weeks or months before a stable cut:

- **RDNA 4 / GFX12**: RadeonSI compute dispatch, buffer/image clears, shader improvements
- **RADV**: Vulkan driver fixes, new extensions, performance tuning
- **NVK / ANV / etc.**: Ongoing Vulkan and OpenGL improvements across all drivers

## Pinned Commit

The pinned upstream commit, hash, version, and date are the single source of
truth in [`version.json`](./version.json) (branch `main`). The daily [`update.yml`](./.github/workflows/update.yml)
workflow runs the custom [`scripts/update.sh`](./scripts/update.sh), which also regenerates
[`wraps.json`](./wraps.json) for the Rust crate dependencies, and commits the new pin to `main`.

<!-- BEGIN generated:installation -->
## Installation

Add as a flake input:

```nix
{
  inputs.mesa-git = {
    url = "github:Daaboulex/mesa-git-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then add the overlay:

```nix
nixpkgs.overlays = [ inputs.mesa-git.overlays.default ];
```

Import the NixOS module:

```nix
imports = [ inputs.mesa-git.nixosModules.default ];
```

<!-- END generated:installation -->

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

By default, mesa-git builds the same drivers as nixpkgs. Set `drivers` to compile only the drivers your hardware needs.

### Vendor Presets

| Vendor | `drivers` | Gallium | Vulkan |
|--------|-----------|---------|--------|
| AMD | `[ "amd" ]` | radeonsi, r600, r300 | `amd` (RADV) |
| Intel | `[ "intel" ]` | iris, crocus, i915 | `intel` (ANV), `intel_hasvk` (HasVK) |
| NVIDIA | `[ "nvidia" ]` | nouveau, tegra | `nouveau` (NVK) |
| All | `[ ]` (default) | nixpkgs' gallium driver list | nixpkgs' vulkan driver list |

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

The overlay applies `overrideAttrs` to nixpkgs' `mesa` derivation and sets `version`, `src`, `patches`, `postPatch`, `outputs`, `mesonFlags`, `postInstall`, `env.MESON_PACKAGE_CACHE_DIR` and `meta.description`. See [`overlay.nix`](./overlay.nix) for each one.

Every other attribute, build inputs and `postFixup` among them, is inherited from nixpkgs. The files under [`overlays/`](./overlays/) are temporary fixes applied on top of that override.

### What the `postPatch` Does

1. **`clang-libdir` meson option**: nixpkgs' `opencl.patch` adds a custom meson option so Nix can control the clang library search path. We replicate this with `substituteInPlace` on `meson.build` and append the option definition from [`clang-libdir-option.meson`](./clang-libdir-option.meson).
2. **Rusticl ICD install**: disables auto-installing the `.icd` file (the overlay's own `postInstall` writes it with an absolute Nix store path).
3. **`mesa-gl-headers` check**: skipped entirely, since git main headers diverge from the pinned release headers package.

## Development

```bash
git clone https://github.com/Daaboulex/mesa-git-nix
cd mesa-git-nix
nix develop                       # enter dev shell, installs pre-commit hooks
nix fmt                           # format flake + module
nix flake check --no-build        # eval check
nix build .#mesa-git              # build the package
nix eval .#mesa-git.version       # confirm pinned commit + version string
```

### Updating the pin

```bash
./scripts/update.sh
```

This script:

1. Reads the latest commit SHA of `main` from `gitlab.freedesktop.org/mesa/mesa` and stops when it is already pinned
2. Computes the source hash by prefetching that commit's archive with `nix store prefetch-file --unpack`
3. Reads Mesa's `VERSION` file at that commit and writes [`version.json`](./version.json)
4. Fetches the commit at depth 1 and regenerates [`wraps.json`](./wraps.json) (Rust crate dependencies) from `subprojects/*.wrap`
5. Rewrites [`venus-protocol.json`](./venus-protocol.json) from Mesa's `subprojects/venus-protocol.wrap` while [`overlays/venus-protocol.nix`](./overlays/venus-protocol.nix) exists
6. Runs `nix flake check` and `nix eval .#mesa-git.version`

After updating, test with:

```bash
nix build .#mesa-git
nix eval .#mesa-git.version
```

CI runs the same chain daily via [`.github/workflows/update.yml`](./.github/workflows/update.yml), so manual updates are rarely needed.

## Verification

After `nixos-rebuild switch`:

```bash
# OpenGL version should show the git version string
glxinfo | grep "OpenGL version"

# Vulkan driver info should show RADV with git version
vulkaninfo | grep driverInfo
```

<!-- BEGIN generated:options -->
## Options

This module declares options under `mesa-git`. See [`module.nix`](module.nix) for all available options.
<!-- END generated:options -->

## License

This packaging flake is [MIT](./LICENSE) licensed. Mesa itself is distributed under the [MIT license](https://docs.mesa3d.org/license.html).

<!-- BEGIN generated:footer -->
<!-- END generated:footer -->
