{
  description = "Mesa-git (bleeding-edge Mesa from main) packaged for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      git-hooks,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      overlays.default = import ./overlay.nix;
      nixosModules.default = import ./module.nix;

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            localSystem.system = system;
            config.allowUnfree = true;
            overlays = [ self.overlays.default ];
          };
        in
        {
          mesa-git = pkgs.mesa-git;
          default = pkgs.mesa-git;
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      checks = forAllSystems (system: {
        pre-commit = git-hooks.lib.${system}.run {
          src = ./.;
          hooks.nixfmt-rfc-style.enable = true;
          hooks.typos.enable = true;
          hooks.rumdl.enable = true;
          hooks.check-readme-sections = {
            enable = true;
            name = "check-readme-sections";
            entry = "bash scripts/check-readme-sections.sh";
            files = "README\.md$";
            language = "system";
          };
        };
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            shellHook = self.checks.${system}.pre-commit.shellHook;
            packages = [ pkgs.nil ];
          };
        }
      );
    };
}
