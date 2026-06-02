final: prev:
let
  lib = prev.lib;
  versionInfo = builtins.fromJSON (builtins.readFile ./version.json);
  rustDeps = lib.importJSON ./wraps.json;

  # mesa main's libdrm floor is the max across enabled drivers (meson
  # `_drm_amdgpu_ver`); the AMDGPU driver currently sets it highest. We do NOT
  # fork libdrm — nixpkgs ships mesa's whole coupled dependency set in lockstep,
  # so mesa inherits it directly. We only assert the floor (inside mesaGitOverride
  # below) so a consumer pinned to an older nixpkgs gets a clear message instead of a deep
  # meson configure error. Bump this when mesa raises `_drm_amdgpu_ver`.
  mesaAmdgpuLibdrmFloor = "2.4.133";

  # Build the Rust crate package cache from our wraps.json.
  #
  # Fetch each crate from the immutable static.crates.io CDN rather than the
  # crates.io/api/v1 download endpoint. That API endpoint is rate-limited and
  # returns 403 to automated CI doing bulk parallel crate downloads (issue #9);
  # the CDN is the canonical immutable store the endpoint redirects to anyway,
  # so the bytes — and thus the pinned hash — are identical. The API endpoint
  # stays on as a fallback mirror; fetchurl tries each url in turn.
  fetchDep =
    dep:
    prev.fetchurl {
      name = "${dep.pname}-${dep.version}.tar.gz";
      urls = [
        "https://static.crates.io/crates/${dep.pname}/${dep.pname}-${dep.version}.crate"
        "https://crates.io/api/v1/crates/${dep.pname}/${dep.version}/download"
      ];
      inherit (dep) hash;
    };

  # Symlink each fetched crate into the cache under the meson-expected name.
  # Keyed off the original dep record (which carries pname/version), not the
  # fetched derivation — fetchurl, unlike fetchCrate, exposes no such passthru.
  packageCacheCommand = lib.pipe rustDeps [
    (map (dep: "ln -s ${fetchDep dep} $out/${dep.pname}-${dep.version}.tar.gz"))
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
  commonGallium = [
    "llvmpipe"
    "softpipe"
    "zink"
    "virgl"
  ];
  commonVulkan = [
    "swrast"
    "virtio"
  ];

  vendorGallium = {
    amd = [
      "radeonsi"
      "r600"
      "r300"
    ];
    intel = [
      "iris"
      "crocus"
      "i915"
    ];
    nvidia = [
      "nouveau"
      "tegra"
    ];
  };

  vendorVulkan = {
    amd = [ "amd" ];
    intel = [
      "intel"
      "intel_hasvk"
    ];
    nvidia = [ "nouveau" ];
  };

  # Resolve a list of vendor names into deduplicated driver lists
  resolveDrivers =
    vendors:
    let
      gallium = lib.unique (commonGallium ++ lib.concatMap (v: vendorGallium.${v} or [ ]) vendors);
      vulkan = lib.unique (commonVulkan ++ lib.concatMap (v: vendorVulkan.${v} or [ ]) vendors);
    in
    {
      inherit gallium vulkan;
    };

  # ===========================================================================
  # Core override — applies git source + patches to any mesa derivation
  # ===========================================================================
  mesaGitOverride =
    baseMesa:
    {
      galliumDrivers ? null,
      vulkanDrivers ? null,
    }:
    let
      # libdrm (and the rest of mesa's build closure) is inherited from nixpkgs,
      # which keeps it in lockstep with mesa. Per-arch is automatic:
      # pkgsi686Linux.mesa already carries the 32-bit libdrm.
      mesa = baseMesa;

      # Effective gallium driver list for output/postInstall decisions. With no
      # custom selection this resolves to nixpkgs' own curated list, so the
      # default build's recipe stays identical to the validated nixpkgs mesa
      # build — only the git src differs. Custom builds narrow to the selection.
      effectiveGallium = if galliumDrivers != null then galliumDrivers else mesa.galliumDrivers or [ ];

      # d3d12 produces spirv2dxil; asahi/panfrost produce cross_tools binaries.
      # Keyed off the effective list (not a "is this a custom build?" guard): the
      # default build keeps every output nixpkgs produces because it builds the
      # full driver set, and a custom build keeps only the outputs its selected
      # drivers actually generate. Decoupling these from the flags is what broke
      # the default build before — outputs were dropped while the drivers that
      # populate them were still being built.
      hasD3d12 = builtins.elem "d3d12" effectiveGallium;
      hasAsahi = builtins.elem "asahi" effectiveGallium;
      hasPanfrost = builtins.elem "panfrost" effectiveGallium;
      hasCrossToolDrivers = hasAsahi || hasPanfrost;

      # Replace driver flags in mesonFlags if custom lists are provided
      overrideDriverFlags =
        flags:
        let
          isDriverFlag = f: lib.hasPrefix "-Dgallium-drivers=" f || lib.hasPrefix "-Dvulkan-drivers=" f;
          filtered = builtins.filter (f: !isDriverFlag f) flags;
        in
        # No custom selection -> keep nixpkgs' explicit driver flags verbatim.
        # Stripping them would drop mesa to meson's `auto` driver set, silently
        # diverging the default build from the validated nixpkgs recipe.
        if galliumDrivers == null && vulkanDrivers == null then
          flags
        else
          filtered
          ++ lib.optional (galliumDrivers != null) (
            lib.mesonOption "gallium-drivers" (lib.concatStringsSep "," galliumDrivers)
          )
          ++ lib.optional (vulkanDrivers != null) (
            lib.mesonOption "vulkan-drivers" (lib.concatStringsSep "," vulkanDrivers)
          );

      # Filter outputs: remove spirv2dxil/cross_tools when their drivers aren't built
      filterOutputs =
        outputs:
        builtins.filter (
          o: (o != "spirv2dxil" || hasD3d12) && (o != "cross_tools" || hasCrossToolDrivers)
        ) outputs;

      # Filter mesonFlags: remove tool/compiler flags when cross_tools drivers aren't built
      filterMesonFlags =
        flags:
        if hasCrossToolDrivers then
          flags
        else
          builtins.filter (
            f:
            !(lib.hasPrefix "-Dtools=" f)
            && !(lib.hasPrefix "-Dinstall-mesa-clc=" f)
            && !(lib.hasPrefix "-Dinstall-precomp-compiler=" f)
          ) flags;

    in
    # Floor check is value-level (per package), not set-level: a set-level assert
    # would force `prev.libdrm` during attribute-name resolution and recurse
    # infinitely through nixpkgs' by-name overlay. Both arches share this libdrm.
    assert lib.assertMsg (lib.versionAtLeast prev.libdrm.version mesaAmdgpuLibdrmFloor) ''
      mesa-git: nixpkgs libdrm ${prev.libdrm.version} is older than ${mesaAmdgpuLibdrmFloor},
      the floor mesa main's AMDGPU driver requires (meson _drm_amdgpu_ver). nixos-unstable
      has shipped libdrm >= ${mesaAmdgpuLibdrmFloor} since 2026-04-27 — update your nixpkgs input.'';
    mesa.overrideAttrs (old: {
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
      patches = [ ];

      postPatch = ''
        patchShebangs .

        # Replicate opencl.patch effect: use clang-libdir meson option instead of
        # the LLVM cmake query. Fail loud if the upstream pattern is gone so an
        # auto-update bump surfaces the drift instead of silently shipping a
        # broken OpenCL build.
        if grep -qF "dep_llvm.get_variable(cmake : 'LLVM_LIBRARY_DIR'" meson.build; then
          substituteInPlace meson.build \
            --replace-fail "dep_llvm.get_variable(cmake : 'LLVM_LIBRARY_DIR', configtool: 'libdir')" \
                           "get_option('clang-libdir')"
        else
          echo "ERROR: clang-libdir pattern not found in meson.build — Mesa changed its LLVM libdir logic; update overlay.nix postPatch." >&2
          exit 1
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

      # Remove outputs that won't be populated with the selected drivers
      outputs = filterOutputs (old.outputs or [ "out" ]);

      mesonFlags = filterMesonFlags (overrideDriverFlags (old.mesonFlags or [ ]));

      # Rewrite postInstall to only move outputs that actually exist
      postInstall = ''
        # cross_tools: only move if the drivers that produce them are built
        ${lib.optionalString hasCrossToolDrivers ''
          moveToOutput bin/asahi_clc $cross_tools
          moveToOutput bin/intel_clc $cross_tools
          moveToOutput bin/mesa_clc $cross_tools
          moveToOutput bin/panfrost_compile $cross_tools
          moveToOutput bin/panfrost_texfeatures $cross_tools
          moveToOutput bin/panfrostdump $cross_tools
          moveToOutput bin/pco_clc $cross_tools
          moveToOutput bin/vtn_bindgen2 $cross_tools
        ''}

        # OpenCL (always built — rusticl is enabled by default)
        moveToOutput "lib/lib*OpenCL*" $opencl
        mkdir -p $opencl/etc/OpenCL/vendors/
        echo $opencl/lib/libRusticlOpenCL.so > $opencl/etc/OpenCL/vendors/rusticl.icd

        # spirv2dxil: only present when d3d12 gallium driver is built
        ${lib.optionalString hasD3d12 ''
          moveToOutput bin/spirv2dxil $spirv2dxil
          moveToOutput "lib/libspirv_to_dxil*" $spirv2dxil
        ''}
      '';

      env = (old.env or { }) // {
        MESON_PACKAGE_CACHE_DIR = packageCache;
      };

      meta = (old.meta or { }) // {
        description = "Mesa (git main) - bleeding-edge 3D graphics library";
      };
    });

in
{
  # Default: all drivers (same as nixpkgs)
  mesa-git = mesaGitOverride prev.mesa { };
  mesa-git-32 = mesaGitOverride prev.pkgsi686Linux.mesa { };

  # Build mesa-git with only the specified vendor drivers + common essentials.
  #
  # Usage:
  #   pkgs.mkMesaGit { vendors = [ "amd" ]; }
  #   pkgs.mkMesaGit { vendors = [ "amd" "intel" ]; }  # iGPU + dGPU
  #   pkgs.mkMesaGit { galliumDrivers = [ "radeonsi" "llvmpipe" ]; vulkanDrivers = [ "amd" ]; }
  #
  mkMesaGit =
    {
      vendors ? [ ],
      galliumDrivers ? null,
      vulkanDrivers ? null,
    }:
    let
      resolved = resolveDrivers vendors;
      gd =
        if galliumDrivers != null then
          galliumDrivers
        else if vendors != [ ] then
          resolved.gallium
        else
          null;
      vd =
        if vulkanDrivers != null then
          vulkanDrivers
        else if vendors != [ ] then
          resolved.vulkan
        else
          null;
    in
    mesaGitOverride prev.mesa {
      galliumDrivers = gd;
      vulkanDrivers = vd;
    };

  mkMesaGit32 =
    {
      vendors ? [ ],
      galliumDrivers ? null,
      vulkanDrivers ? null,
    }:
    let
      resolved = resolveDrivers vendors;
      gd =
        if galliumDrivers != null then
          galliumDrivers
        else if vendors != [ ] then
          resolved.gallium
        else
          null;
      vd =
        if vulkanDrivers != null then
          vulkanDrivers
        else if vendors != [ ] then
          resolved.vulkan
        else
          null;
    in
    mesaGitOverride prev.pkgsi686Linux.mesa {
      galliumDrivers = gd;
      vulkanDrivers = vd;
    };

  # Expose presets and resolver for downstream modules
  mesa-git-lib = {
    inherit
      vendorGallium
      vendorVulkan
      commonGallium
      commonVulkan
      resolveDrivers
      ;
  };
}
