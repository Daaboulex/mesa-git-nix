# mesa-git-nix

[Mesa](https://www.mesa3d.org/), the 3D graphics library, built from the
`main` branch of its upstream repository and packaged as a Nix flake. It is
for a NixOS user who wants driver work before it reaches a stable release.
nixpkgs-unstable tracks the stable releases, and `main` often has driver
improvements weeks or months earlier.

## Does it work

The flake offers `mesa-git` for x86_64-linux and aarch64-linux. The 32-bit
build, `mesa-git-32`, exists on x86_64-linux only.

The pin moves often. A workflow sets it to the newest commit on `main`, daily
by default. Nothing in this repository records which graphics cards it has
been run on.

## Install

Add the flake. Its own nixpkgs input is nixos-unstable.

```nix
{
  inputs.mesa-git-nix = {
    url = "github:Daaboulex/mesa-git-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then import the module, add the overlay and switch it on.

```nix
{ inputs, ... }:
{
  imports = [ inputs.mesa-git-nix.nixosModules.default ];
  nixpkgs.overlays = [ inputs.mesa-git-nix.overlays.default ];

  mesa-git.enable = true;
}
```

The module points `hardware.graphics.package` and
`hardware.graphics.package32` at the git build. With nothing else set, it
builds the same drivers nixpkgs builds.

## Build only the drivers you need

`mesa-git.drivers` takes a list of vendors and compiles only their drivers,
for example `mesa-git.drivers = [ "amd" ];`.

| `drivers` | Gallium drivers | Vulkan drivers |
|---|---|---|
| `[ "amd" ]` | radeonsi, r600, r300 | amd (RADV) |
| `[ "intel" ]` | iris, crocus, i915 | intel (ANV), intel_hasvk (HasVK) |
| `[ "nvidia" ]` | nouveau, tegra | nouveau (NVK) |
| `[ ]`, the default | the list nixpkgs builds | the list nixpkgs builds |

Every vendor selection also builds llvmpipe, softpipe, zink and virgl for
Gallium, and swrast and virtio for Vulkan. Those are the software renderers,
OpenGL over Vulkan and the drivers for virtual machines.

A machine with two graphics cards lists both vendors, for example
`[ "intel" "nvidia" ]` for an Intel integrated card beside an NVIDIA one.

Both options, with type and default: [docs/OPTIONS.md](docs/OPTIONS.md).

## Check that it is in use

After `nixos-rebuild switch`:

```bash
glxinfo | grep "OpenGL version"
vulkaninfo | grep driverInfo
```

The OpenGL version should show the git version string, which is Mesa's
version followed by the first seven characters of the pinned commit. On an
AMD card the Vulkan driver info should show RADV with the git version.

## Without the module

The overlay alone is enough if you set `hardware.graphics.package` yourself.
It adds `pkgs.mesa-git` and `pkgs.mesa-git-32`, which build every driver
nixpkgs builds. It also adds two functions that narrow the build,
`pkgs.mkMesaGit` and `pkgs.mkMesaGit32`.

```nix
{ inputs, pkgs, lib, ... }:
{
  nixpkgs.overlays = [ inputs.mesa-git-nix.overlays.default ];

  hardware.graphics.package = lib.mkForce (pkgs.mkMesaGit { vendors = [ "amd" ]; });
  hardware.graphics.package32 = lib.mkForce (pkgs.mkMesaGit32 { vendors = [ "amd" ]; });
}
```

Both functions also take exact driver lists, `galliumDrivers` and
`vulkanDrivers`, in place of vendors. An exact list is used as written, with
nothing added to it.

To build the package on its own:

```bash
nix build github:Daaboulex/mesa-git-nix
nix eval github:Daaboulex/mesa-git-nix#mesa-git.version
```

## Known limits

- Your nixpkgs must carry libdrm 2.4.133 or newer. An older one stops the
  evaluation with a message that tells you to update nixpkgs.
- The vendor presets cover AMD, Intel and NVIDIA only. Any other driver needs
  an exact list through `pkgs.mkMesaGit`.
- A build narrowed by vendor has no `spirv2dxil` and no `cross_tools` output,
  because the drivers that fill them are not built.
- While the module is on it sets both graphics packages with `lib.mkForce`,
  so a plain value of your own for `hardware.graphics.package` loses.

## When it breaks

Set `mesa-git.enable = false` and rebuild. The module then sets nothing, and
the system is back on the Mesa that nixpkgs ships.

Security problems in the packaging are reported privately, as
[SECURITY.md](SECURITY.md) describes.

## More

- [docs/DESIGN.md](docs/DESIGN.md): why it tracks `main`, how the overlay
  changes the nixpkgs recipe, which drivers every preset includes
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): building, the checks, how the
  pin is updated

## License

This packaging flake is [MIT](./LICENSE) licensed. Mesa itself is distributed under the [MIT license](https://docs.mesa3d.org/license.html).
