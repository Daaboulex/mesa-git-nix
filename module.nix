{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mesa-git;

  mesaPkg = if cfg.drivers == [ ] then pkgs.mesa-git else pkgs.mkMesaGit { vendors = cfg.drivers; };

  mesaPkg32 =
    if cfg.drivers == [ ] then pkgs.mesa-git-32 else pkgs.mkMesaGit32 { vendors = cfg.drivers; };
in
{
  options.mesa-git = {
    enable = lib.mkEnableOption "Use mesa-git (bleeding-edge) instead of nixpkgs mesa";

    drivers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "amd"
          "intel"
          "nvidia"
        ]
      );
      default = [ ];
      example = [ "amd" ];
      description = ''
        GPU vendors to compile drivers for. Only the selected vendor drivers
        plus common essentials (llvmpipe, zink, virgl, swrast) are built.

        Use multiple entries for multi-GPU setups (e.g. Intel iGPU + NVIDIA dGPU).
        An empty list (default) builds all drivers.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics.package = lib.mkForce mesaPkg;
    hardware.graphics.package32 = lib.mkForce mesaPkg32;
  };
}
