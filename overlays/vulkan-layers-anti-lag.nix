{
  meta = {
    reason = "mesa main deleted the anti-lag Vulkan layer (RADV implements VK_AMD_anti_lag itself), and nixpkgs' mesa recipe still enables it, so meson refuses the inherited flag at configure";
    added = "2026-11-04";
    upstream = "https://gitlab.freedesktop.org/mesa/mesa/-/commit/b99595dedb854de80aaaf87c06c93940e90b4122";
  };
  dropWhen =
    pkgs:
    !builtins.any (
      f:
      pkgs.lib.hasPrefix "-Dvulkan-layers=" f
      && builtins.elem "anti-lag" (pkgs.lib.splitString "," (pkgs.lib.removePrefix "-Dvulkan-layers=" f))
    ) pkgs.mesa-git.mesonFlags;
  overlay =
    _final: prev:
    let
      inherit (prev) lib;
      prefix = "-Dvulkan-layers=";
      withoutAntiLag =
        f:
        if lib.hasPrefix prefix f then
          prefix
          + lib.concatStringsSep "," (
            builtins.filter (l: l != "anti-lag") (lib.splitString "," (lib.removePrefix prefix f))
          )
        else
          f;
      fix =
        drv:
        drv.overrideAttrs (old: {
          mesonFlags = map withoutAntiLag old.mesonFlags;
        });
    in
    {
      mesa-git = fix prev.mesa-git;
      mesa-git-32 = fix prev.mesa-git-32;
      mkMesaGit = args: fix (prev.mkMesaGit args);
      mkMesaGit32 = args: fix (prev.mkMesaGit32 args);
    };
}
