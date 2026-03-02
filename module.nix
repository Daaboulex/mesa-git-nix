{ config, lib, pkgs, ... }:
let
  cfg = config.mesa-git;
in {
  options.mesa-git.enable = lib.mkEnableOption "Use mesa-git (bleeding-edge) instead of nixpkgs mesa";

  config = lib.mkIf cfg.enable {
    hardware.graphics.package = lib.mkForce pkgs.mesa-git;
    hardware.graphics.package32 = lib.mkForce pkgs.mesa-git-32;
  };
}
