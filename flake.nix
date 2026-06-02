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
      url = "github:Daaboulex/nix-packaging-standard?ref=v2.3.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.git-hooks.follows = "git-hooks";
    };
  };

  outputs =
    inputs@{ flake-parts, self, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # The 32-bit variant (mesa-git-32 via pkgsi686Linux) and the module's
      # package32 are x86_64-only; aarch64 has no pkgsi686Linux. declared==built.
      systems = [ "x86_64-linux" ];

      imports = [ inputs.std.flakeModules.base ];

      flake.overlays.default = import ./overlay.nix;
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
          packages.mesa-git = pkgs.mesa-git;
          packages.default = pkgs.mesa-git;

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
