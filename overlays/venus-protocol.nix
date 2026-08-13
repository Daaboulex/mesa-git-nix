# Mesa main requires the venus-protocol wrap-git subproject whenever a virtio
# vulkan driver is built (meson.build: dependency('venus-protocol', fallback)),
# and nixpkgs' mesa recipe carries nothing for it. venus-protocol upstream
# installs no headers and no pkg-config file -- it is only consumable as a
# meson subproject -- so materialize the pinned source at the wrap's directory
# and let mesa's own declared fallback build it without downloading.
{
  meta = {
    reason = "mesa main needs the venus-protocol subproject; upstream installs no .pc and nixpkgs' mesa recipe does not provide it; venus-protocol.json is rewritten by update.sh from mesa's own wrap while this fix exists";
    added = "2026-08-11";
    upstream = "https://gitlab.freedesktop.org/virgl/venus-protocol";
  };
  # Healed when the un-fixed mesa-git BUILDS: either the inherited nixpkgs
  # recipe provides venus-protocol or mesa stopped requiring it.
  dropWhenBuilds = pkgs: pkgs.mesa-git;
  overlay =
    _final: prev:
    let
      pin = prev.lib.importJSON ../venus-protocol.json;
      src = prev.fetchFromGitLab {
        domain = "gitlab.freedesktop.org";
        owner = "virgl";
        repo = "venus-protocol";
        inherit (pin) rev hash;
      };
      addVenus =
        drv:
        drv.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            cp -r --no-preserve=mode ${src} subprojects/${pin.directory}
          '';
        });
    in
    {
      mesa-git = addVenus prev.mesa-git;
      mesa-git-32 = addVenus prev.mesa-git-32;
      mkMesaGit = args: addVenus (prev.mkMesaGit args);
      mkMesaGit32 = args: addVenus (prev.mkMesaGit32 args);
    };
}
