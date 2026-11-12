# Design

Why mesa-git-nix is built the way it is.

## Upstream

Upstream is the Mesa project at <https://gitlab.freedesktop.org/mesa/mesa>,
under the MIT license. This flake tracks the Git HEAD of its `main` branch.

## Why track main

nixpkgs-unstable tracks Mesa stable releases. Mesa `main` often contains
unreleased driver optimizations weeks or months before a stable cut:

- RDNA 4 / GFX12: RadeonSI compute dispatch, buffer/image clears, shader
  improvements
- RADV: Vulkan driver fixes, new extensions, performance tuning
- NVK / ANV / etc.: ongoing Vulkan and OpenGL improvements across all drivers

## An override, not a rewrite

The overlay overrides nixpkgs' `mesa` through `overrideAttrs`, so no
derivation rewrite is needed. It sets `version`, `src`, `patches`,
`postPatch`, `outputs`, `mesonFlags`, `postInstall`,
`env.MESON_PACKAGE_CACHE_DIR` and `meta.description`. See
[`overlay.nix`](../overlay.nix) for each one.

Every other attribute, build inputs and `postFixup` among them, is inherited
from nixpkgs. The files under [`overlays/`](../overlays/) are temporary fixes
applied on top of that override.

## What the postPatch does

1. The `clang-libdir` meson option. nixpkgs' `opencl.patch` adds a custom
   meson option so Nix can control the clang library search path. The overlay
   replicates this with `substituteInPlace` on `meson.build` and appends the
   option definition from
   [`clang-libdir-option.meson`](../clang-libdir-option.meson).
2. The Rusticl ICD install. Auto-installing the `.icd` file is disabled, and
   the overlay's own `postInstall` writes it with an absolute Nix store path.
3. The `mesa-gl-headers` check. It is skipped entirely, since git main headers
   diverge from the pinned release headers package.

## Driver presets

By default mesa-git builds the same drivers as nixpkgs. A vendor preset
replaces both driver lists with that vendor's drivers plus a common set. The
README has the table of what each vendor builds.

The common set is built regardless of vendor selection:

- Gallium: llvmpipe (software fallback), softpipe, zink (OpenGL-over-Vulkan),
  virgl (VM)
- Vulkan: Lavapipe/swrast (software fallback), virtio (VM)

For full control, use `mkMesaGit` / `mkMesaGit32` directly:

```nix
hardware.graphics.package = lib.mkForce (pkgs.mkMesaGit {
  galliumDrivers = [ "radeonsi" "llvmpipe" "zink" ];
  vulkanDrivers = [ "amd" "swrast" ];
});
```
