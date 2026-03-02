final: prev:
let
  lib = prev.lib;
  versionInfo = builtins.fromJSON (builtins.readFile ./version.json);
  rustDeps = lib.importJSON ./wraps.json;

  # Build the Rust crate package cache from our wraps.json
  fetchDep = dep: prev.fetchCrate {
    inherit (dep) pname version hash;
    unpack = false;
  };

  toCommand = dep: "ln -s ${dep} $out/${dep.pname}-${dep.version}.tar.gz";

  packageCacheCommand = lib.pipe rustDeps [
    (map fetchDep)
    (map toCommand)
    (lib.concatStringsSep "\n")
  ];

  packageCache = prev.runCommand "mesa-git-rust-package-cache" { } ''
    mkdir -p $out
    ${packageCacheCommand}
  '';

  # ===========================================================================
  # Driver presets — vendor-specific + common essentials
  # ===========================================================================
  #
  # Common drivers are always included regardless of vendor selection:
  #   - llvmpipe/softpipe: software renderers (fallback, CI, headless)
  #   - zink: OpenGL-over-Vulkan (compatibility layer)
  #   - virgl: virtio-gpu for VMs
  #   - swrast (vulkan): Lavapipe software Vulkan
  #   - virtio (vulkan): virtio-gpu native context for VMs
  #
  commonGallium = [ "llvmpipe" "softpipe" "zink" "virgl" ];
  commonVulkan  = [ "swrast" "virtio" ];

  vendorGallium = {
    amd    = [ "radeonsi" "r600" "r300" ];
    intel  = [ "iris" "crocus" "i915" ];
    nvidia = [ "nouveau" "tegra" ];
  };

  vendorVulkan = {
    amd    = [ "amd" ];
    intel  = [ "intel" "intel_hasvk" ];
    nvidia = [ "nouveau" ];
  };

  # Resolve a list of vendor names into deduplicated driver lists
  resolveDrivers = vendors:
    let
      gallium = lib.unique (commonGallium ++ lib.concatMap (v: vendorGallium.${v} or []) vendors);
      vulkan  = lib.unique (commonVulkan  ++ lib.concatMap (v: vendorVulkan.${v}  or []) vendors);
    in { inherit gallium vulkan; };

  # ===========================================================================
  # Core override — applies git source + patches to any mesa derivation
  # ===========================================================================
  mesaGitOverride = mesa: { galliumDrivers ? null, vulkanDrivers ? null }:
    let
      # Replace driver flags in mesonFlags if custom lists are provided
      overrideDriverFlags = flags:
        let
          isDriverFlag = f:
            lib.hasPrefix "-Dgallium-drivers=" f || lib.hasPrefix "-Dvulkan-drivers=" f;
          filtered = builtins.filter (f: !isDriverFlag f) flags;
        in filtered
          ++ lib.optional (galliumDrivers != null)
            (lib.mesonOption "gallium-drivers" (lib.concatStringsSep "," galliumDrivers))
          ++ lib.optional (vulkanDrivers != null)
            (lib.mesonOption "vulkan-drivers" (lib.concatStringsSep "," vulkanDrivers));
    in mesa.overrideAttrs (old: {
      version = "${versionInfo.version}-${builtins.substring 0 7 versionInfo.rev}";

      src = prev.fetchFromGitLab {
        domain = "gitlab.freedesktop.org";
        owner = "mesa";
        repo = "mesa";
        inherit (versionInfo) rev hash;
      };

      # nixpkgs' opencl.patch targets specific line numbers that won't match git main.
      # The underlying changes (clang-libdir option, rusticl ICD install disable) are
      # handled: clang-libdir is passed via mesonFlags, and the ICD path is reconstructed
      # in postInstall. We reapply just the functional parts via postPatch.
      patches = [];

      postPatch = ''
        patchShebangs .

        # Replicate opencl.patch effect: use clang-libdir meson option instead of llvm query
        if grep -q "dep_llvm.get_variable(cmake : 'LLVM_LIBRARY_DIR'" meson.build 2>/dev/null; then
          substituteInPlace meson.build \
            --replace-fail "dep_llvm.get_variable(cmake : 'LLVM_LIBRARY_DIR', configtool: 'libdir')" \
                           "get_option('clang-libdir')"
        fi

        # Add clang-libdir meson option if not already present
        if ! grep -q "clang-libdir" meson.options 2>/dev/null; then
          cat ${./clang-libdir-option.meson} >> meson.options
        fi

        # Disable rusticl ICD file auto-install (nixpkgs constructs its own with absolute path)
        # Only target the configure_file block, not the shared_library install
        if [ -f src/gallium/targets/rusticl/meson.build ]; then
          sed -i '/configure_file/,/^)/{s/install : true/install : false/}' \
            src/gallium/targets/rusticl/meson.build || true
        fi
      '';

      mesonFlags = overrideDriverFlags (old.mesonFlags or []);

      env = (old.env or {}) // {
        MESON_PACKAGE_CACHE_DIR = packageCache;
      };

      meta = (old.meta or {}) // {
        description = "Mesa (git main) - bleeding-edge 3D graphics library";
      };
    });

in {
  # Default: all drivers (same as nixpkgs)
  mesa-git    = mesaGitOverride prev.mesa {};
  mesa-git-32 = mesaGitOverride prev.pkgsi686Linux.mesa {};

  # Build mesa-git with only the specified vendor drivers + common essentials.
  #
  # Usage:
  #   pkgs.mkMesaGit { vendors = [ "amd" ]; }
  #   pkgs.mkMesaGit { vendors = [ "amd" "intel" ]; }  # iGPU + dGPU
  #   pkgs.mkMesaGit { galliumDrivers = [ "radeonsi" "llvmpipe" ]; vulkanDrivers = [ "amd" ]; }
  #
  mkMesaGit = { vendors ? [], galliumDrivers ? null, vulkanDrivers ? null }:
    let
      resolved = resolveDrivers vendors;
      gd = if galliumDrivers != null then galliumDrivers else if vendors != [] then resolved.gallium else null;
      vd = if vulkanDrivers  != null then vulkanDrivers  else if vendors != [] then resolved.vulkan  else null;
    in mesaGitOverride prev.mesa { galliumDrivers = gd; vulkanDrivers = vd; };

  mkMesaGit32 = { vendors ? [], galliumDrivers ? null, vulkanDrivers ? null }:
    let
      resolved = resolveDrivers vendors;
      gd = if galliumDrivers != null then galliumDrivers else if vendors != [] then resolved.gallium else null;
      vd = if vulkanDrivers  != null then vulkanDrivers  else if vendors != [] then resolved.vulkan  else null;
    in mesaGitOverride prev.pkgsi686Linux.mesa { galliumDrivers = gd; vulkanDrivers = vd; };

  # Expose presets and resolver for downstream modules
  mesa-git-lib = { inherit vendorGallium vendorVulkan commonGallium commonVulkan resolveDrivers; };
}
