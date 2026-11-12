# Development

Building, the checks and how the pin is updated.

## Building and checking

```bash
git clone https://github.com/Daaboulex/mesa-git-nix
cd mesa-git-nix
nix develop
nix fmt
nix flake check --no-build
nix build .#mesa-git
nix eval .#mesa-git.version
```

`nix develop` enters the dev shell and installs the pre-commit hooks. `nix fmt`
formats the flake and the module. `nix flake check --no-build` is the
evaluation check.

`nix build .#mesa-git` builds the package. `nix eval .#mesa-git.version`
confirms the pinned commit and the version string.

CI is [`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## The pinned commit

The pinned upstream commit, hash, version and date are the single source of
truth in [`version.json`](../version.json) (branch `main`). The daily
[`update.yml`](../.github/workflows/update.yml) workflow runs the custom
[`scripts/update.sh`](../scripts/update.sh), which also regenerates
[`wraps.json`](../wraps.json) for the Rust crate dependencies, and commits the
new pin to `main`.

Daily is the default. With the `UPDATE_CADENCE` repository variable set to
`weekly`, only the Sunday run happens.

## Updating the pin by hand

```bash
./scripts/update.sh
```

This script:

1. Reads the latest commit SHA of `main` from
   `gitlab.freedesktop.org/mesa/mesa` and stops when it is already pinned
2. Computes the source hash by prefetching that commit's archive with
   `nix store prefetch-file --unpack`
3. Reads Mesa's `VERSION` file at that commit and writes
   [`version.json`](../version.json)
4. Fetches the commit at depth 1 and regenerates [`wraps.json`](../wraps.json)
   (Rust crate dependencies) from `subprojects/*.wrap`
5. Rewrites [`venus-protocol.json`](../venus-protocol.json) from Mesa's
   `subprojects/venus-protocol.wrap` while
   [`overlays/venus-protocol.nix`](../overlays/venus-protocol.nix) exists
6. Runs `nix flake check` and `nix eval .#mesa-git.version`

After updating, test with:

```bash
nix build .#mesa-git
nix eval .#mesa-git.version
```

CI runs the same chain daily via
[`.github/workflows/update.yml`](../.github/workflows/update.yml), so manual
updates are rarely needed.
