let
  legacyPrefixes = [
    "-Damdgpu-virtio="
    "-Damd-use-llvm="
  ];
  isLegacy = lib: f: builtins.any (p: lib.hasPrefix p f) legacyPrefixes;
in
{
  meta = {
    reason = "mesa main folded the booleans amdgpu-virtio and amd-use-llvm into the array option amd-options, and its deprecation shim cannot map nixpkgs' -Damdgpu-virtio=true onto an array, so meson refuses it at configure";
    added = "2026-11-04";
    upstream = "https://gitlab.freedesktop.org/mesa/mesa/-/commit/175f0718df1cb3d97364c09ec6e82df6c53c1a5e";
  };
  dropWhen = pkgs: !builtins.any (isLegacy pkgs.lib) pkgs.mesa-git.mesonFlags;
  overlay =
    _final: prev:
    let
      inherit (prev) lib;
      migrate =
        flags:
        if !builtins.any (isLegacy lib) flags then
          flags
        else
          assert lib.assertMsg (!builtins.any (lib.hasPrefix "-Damd-options=") flags) ''
            mesa-git: nixpkgs passes -Damd-options beside the legacy amdgpu-virtio or amd-use-llvm,
            so overlays/amd-options.nix cannot tell which one mesa main should honour.'';
          builtins.filter (f: !isLegacy lib f) flags
          ++ [
            (lib.mesonOption "amd-options" (
              lib.concatStringsSep "," (
                lib.optional (!builtins.elem "-Damd-use-llvm=false" flags) "use-llvm"
                ++ lib.optional (builtins.elem "-Damdgpu-virtio=true" flags) "virtio"
              )
            ))
          ];
      fix =
        drv:
        drv.overrideAttrs (old: {
          mesonFlags = migrate old.mesonFlags;
        });
    in
    {
      mesa-git = fix prev.mesa-git;
      mesa-git-32 = fix prev.mesa-git-32;
      mkMesaGit = args: fix (prev.mkMesaGit args);
      mkMesaGit32 = args: fix (prev.mkMesaGit32 args);
    };
}
