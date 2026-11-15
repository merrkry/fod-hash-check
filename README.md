# fod-hash-check

GitHub Action that verifies the declared hashes of fixed-output derivations (FODs) in a Nix flake, and skips the check when the derivations have not changed since the last success.

A stale FOD hash does not always fail the build. The output path of an FOD depends only on its name and hash, so if the old output is already in the store or a substituter, Nix uses it and never runs the fetch. This action rebuilds the FODs with `nix build --rebuild`, which runs the fetch again and compares the result with the declared hash.

Rebuilding is slow for large fetches, such as pnpm or Cargo dependencies. After a successful check, the action caches a marker keyed by the derivations, so later runs skip the rebuild until a checked derivation changes.

## Usage

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
        with:
          attributes: |
            web.pnpmDeps
            server.cargoDeps
```

To also catch sources that disappear upstream, run the check without the cache on a schedule:

```yaml
on:
  schedule:
    - cron: "0 4 * * 1"

# ...
      - uses: merrkry/fod-hash-check@v0.1.0
        with:
          attributes: web.pnpmDeps
          use-cache: false
```

## Inputs

| Input        | Default  | Description                                                                                                      |
| ------------ | -------- | ---------------------------------------------------------------------------------------------------------------- |
| `attributes` | required | Attribute paths under `packages.<system>` of the flake, separated by whitespace or newlines.                     |
| `flake`      | `.`      | Flake reference.                                                                                                 |
| `use-cache`  | `true`   | Skip the check when a success for the same key is cached. With `false`, always check, and still cache a success. |

Attribute paths are dot-separated names, such as `web.pnpmDeps`. The action quotes each name, so names like `app+web` need no quoting. Names containing `.`, `"`, `\`, or `$` are not supported.

## Outputs

| Output      | Description                                                                         |
| ----------- | ----------------------------------------------------------------------------------- |
| `key`       | SHA-256 over the check version, the current system, and the attributes' `drvPath`s. |
| `cache-hit` | `true` if the check was skipped because a success for `key` was cached.             |

## How it works

1. Evaluates the `drvPath` of every attribute in one `nix eval` and hashes them, together with the system and a check version, into `key`. The Nix version and other tooling are not part of the key, since they do not change whether a declared hash is correct.
2. Looks up a cache entry for `key` without downloading it.
3. On a miss, or with `use-cache: false`, runs `nix build --no-link` to make the outputs valid, then `nix build --no-link --rebuild` to fetch them again and compare.
4. Saves the cache entry right after the check succeeds, so a later failing step in the job does not discard the result.

The marker file exists in the workspace only while it is being saved, so the action leaves the checkout unchanged.

## Prerequisites

- Nix with flakes enabled, installed by an earlier step, such as [NixOS/nix-installer-action](https://github.com/NixOS/nix-installer-action). The action does not install Nix.
- Credentials the fetches need, such as GitHub access tokens in `NIX_CONFIG`.
