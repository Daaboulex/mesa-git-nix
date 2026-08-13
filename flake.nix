{
  description = "Mesa-git (bleeding-edge Mesa from main) packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    std = {
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.22.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # mesa-git builds on both arches; the 32-bit variant (mesa-git-32 via
      # pkgsi686Linux) and the module's package32 stay x86_64-only -- aarch64 has
      # no pkgsi686Linux, so they are simply absent there (declared == built).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays =
        let
          glueOverlay = import ./overlay.nix;
          dir = ./overlays;
          names = if builtins.pathExists dir then builtins.attrNames (builtins.readDir dir) else [ ];
          fixOverlays = map (n: (import (dir + "/${n}")).overlay) (
            builtins.filter (n: inputs.nixpkgs.lib.hasSuffix ".nix" n) names
          );
        in
        {
          # Glue + temporary fixes -- what consumers and this flake apply.
          default = inputs.nixpkgs.lib.composeManyExtensions ([ glueOverlay ] ++ fixOverlays);
          # Glue WITHOUT fixes -- heal-overlays.sh probes dropWhen against this.
          probe = glueOverlay;
        };
      flake.nixosModules.default = import ./module.nix;

      perSystem =
        { system, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ self.overlays.default ];
          };
        in
        {
          packages = {
            inherit (pkgs) mesa-git;
            default = pkgs.mesa-git;
          }
          // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
            inherit (pkgs) mesa-git-32;
          };

          checks.module-eval-nixos = inputs.std.lib.nixosModuleCheck {
            inherit (inputs) nixpkgs;
            inherit system;
            overlays = [ self.overlays.default ];
            module = ./module.nix;
            config = {
              nixpkgs.config.allowUnfree = true;
              mesa-git.enable = true;
            };
          };
        };
    };
}
