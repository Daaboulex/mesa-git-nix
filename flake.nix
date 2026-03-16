{
  description = "Mesa-git (bleeding-edge Mesa from main) packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in {
    overlays.default = import ./overlay.nix;
    nixosModules.default = import ./module.nix;

    packages = forAllSystems (system:
      let
        pkgs = import nixpkgs {
          localSystem.system = system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        };
      in {
        mesa-git = pkgs.mesa-git;
        default = pkgs.mesa-git;
      }
    );
  };
}
