final: prev:
let
  versionInfo = builtins.fromJSON (builtins.readFile ./version.json);
  rustDeps = prev.lib.importJSON ./wraps.json;

  # Build the Rust crate package cache from our wraps.json
  fetchDep = dep: prev.fetchCrate {
    inherit (dep) pname version hash;
    unpack = false;
  };

  toCommand = dep: "ln -s ${dep} $out/${dep.pname}-${dep.version}.tar.gz";

  packageCacheCommand = prev.lib.pipe rustDeps [
    (map fetchDep)
    (map toCommand)
    (prev.lib.concatStringsSep "\n")
  ];

  packageCache = prev.runCommand "mesa-git-rust-package-cache" { } ''
    mkdir -p $out
    ${packageCacheCommand}
  '';

  mesaGitOverride = mesa: mesa.overrideAttrs (old: {
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
    # in postInstall. We reapply just the functional parts via postPatch sed commands.
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
        cat >> meson.options << 'MESAOPT'

      option(
        'clang-libdir',
        type : 'string',
        value : '',
        description : 'Locations to search for clang libraries.'
      )
      MESAOPT
      fi

      # Disable rusticl ICD auto-install (nixpkgs constructs its own with absolute path)
      if [ -f src/gallium/targets/rusticl/meson.build ]; then
        substituteInPlace src/gallium/targets/rusticl/meson.build \
          --replace-fail "install : true," "install : false," || true
      fi
    '';
    # Skip mesa-gl-headers validation — git main headers won't match the pinned release

    # Override the Rust crate package cache with versions matching git main
    env = (old.env or {}) // {
      MESON_PACKAGE_CACHE_DIR = packageCache;
    };

    meta = (old.meta or {}) // {
      description = "Mesa (git main) - bleeding-edge 3D graphics library";
    };
  });
in {
  mesa-git = mesaGitOverride prev.mesa;
  mesa-git-32 = mesaGitOverride prev.pkgsi686Linux.mesa;
}
