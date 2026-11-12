# Options

Every option the modules of this flake declare. This file is generated from the module sources: change a description there, then run `nix run .#std-write-option-reference`.

## NixOS module

Declared in [module.nix](../module.nix).

### `mesa-git.enable`

Whether to enable Use mesa-git (bleeding-edge) instead of nixpkgs mesa.

- Type: boolean
- Default: `false`

### `mesa-git.drivers`

GPU vendors to compile drivers for. Only the selected vendor drivers
plus common essentials (llvmpipe, zink, virgl, swrast) are built.

Use multiple entries for multi-GPU setups (e.g. Intel iGPU + NVIDIA dGPU).
An empty list (default) builds all drivers.

- Type: list of (one of "amd", "intel", "nvidia")
- Default: `[ ]`
- Example:

  ```nix
  [
    "amd"
  ]
  ```
