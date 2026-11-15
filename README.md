# fod-hash-check

GitHub Action that verifies the declared hashes of fixed-output derivations (FODs), and skips the check when the derivations have not changed since the last success.

A stale FOD hash does not always fail the build. The output path of an FOD depends only on its name and hash, so if the old output is already in the store or a substituter, Nix uses it and never runs the fetch. This action rebuilds the FODs with `nix build --rebuild`, which runs the fetch again and compares the result with the declared hash.

Rebuilding is slow for large fetches, such as pnpm or Cargo dependencies. After a successful check, the action caches a marker keyed by the derivations, so later runs skip the rebuild until a checked derivation changes.

## Usage

List the FODs to check in `fod-hashes.toml` at the repository root:

```toml
[web]
installable = ".#web.pnpmDeps"
file = "nix/web.nix"

[server]
installable = ".#server.cargoDeps"
```

Then run the action after installing Nix:

```yaml
jobs:
  check:
    runs-on: ubuntu-latest
    env:
      # Authenticate GitHub fetches; shared runner IPs exhaust the anonymous API limit.
      NIX_CONFIG: access-tokens = github.com=${{ github.token }}
    steps:
      - uses: actions/checkout@v7
      - uses: NixOS/nix-installer-action@v1
      - uses: merrkry/fod-hash-check@v0.1.0
```

To skip the file, list the installables in the workflow instead:

```yaml
- uses: merrkry/fod-hash-check@v0.1.0
  with:
    installables: |
      .#web.pnpmDeps
      .#server.cargoDeps
```

To also catch sources that disappear upstream, run the check without the cache on a schedule:

```yaml
on:
  schedule:
    - cron: "0 4 * * 1"

# ...
- uses: merrkry/fod-hash-check@v0.1.0
  with:
    use-cache: false
```

## Inputs

| Input          | Default           | Description                                                                                                      |
| -------------- | ----------------- | ---------------------------------------------------------------------------------------------------------------- |
| `config`       | `fod-hashes.toml` | TOML file listing the FODs to check. Read only when `installables` is not set.                                   |
| `installables` |                   | Nix installables to check, separated by whitespace or newlines. Set either this or `config`, not both.           |
| `use-cache`    | `true`            | Skip the check when a success for the same key is cached. With `false`, always check, and still cache a success. |

Installables follow the same rules as `nix build`: `.#web.pnpmDeps` resolves to `packages.<system>.web.pnpmDeps` or `legacyPackages.<system>.web.pnpmDeps`, and full attribute paths such as `.#checks.x86_64-linux.foo` also work. Relative flake references like `.` resolve against the workspace, not the config file. Lock files are not written.

Each installable must be a fixed-output derivation, such as `.#web.pnpmDeps` rather than `.#web`. The action fails on any other derivation, since rebuilding it verifies no hash.

## Config file

Each table in the config file is a target. The table name identifies the target, and these fields describe it:

| Field         | Required | Description                                                                             |
| ------------- | -------- | --------------------------------------------------------------------------------------- |
| `installable` | yes      | Nix installable of the FOD.                                                             |
| `file`        | no       | File that declares the FOD's hash, for tools that update hashes. The action ignores it. |

The action ignores other fields as well.

## Outputs

| Output      | Description                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------- |
| `key`       | SHA-256 over the check version, the current system, and the installables' derivation paths. |
| `cache-hit` | `true` if the check was skipped because a success for `key` was cached.                     |

## How it works

1. Evaluates all installables in one `nix derivation show`, fails if any of them has no fixed output hash, and hashes their derivation paths, together with the system and a check version, into `key`. Different spellings of the same derivations share a key. The Nix version and other tooling are not part of the key, since they do not change whether a declared hash is correct.
2. Looks up a cache entry for `key` without downloading it.
3. On a miss, or with `use-cache: false`, builds the evaluated derivations with `nix build --no-link` to make the outputs valid, then with `nix build --no-link --rebuild` to fetch them again and compare. Both builds use `--keep-going`, so one run reports every mismatch.
4. Saves the cache entry right after the check succeeds, so a later failing step in the job does not discard the result.

The marker file exists in the workspace only while it is being saved, so the action leaves the checkout unchanged.

## Prerequisites

- Nix with flakes enabled, installed by an earlier step, such as [NixOS/nix-installer-action](https://github.com/NixOS/nix-installer-action). The action does not install Nix.
- Credentials the fetches need, such as GitHub access tokens in `NIX_CONFIG`.
