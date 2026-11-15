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

| Input          | Default           | Description                                                                                                                                   |
| -------------- | ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `config`       | `fod-hashes.toml` | TOML file listing the FODs to check. Read only when `installables` is not set.                                                                |
| `installables` |                   | Nix installables to check, separated by whitespace or newlines. Set either this or `config`, not both.                                        |
| `use-cache`    | `true`            | Skip the check when a success for the same key is cached. With `false`, always check, and still cache a success.                              |
| `update`       | `false`           | On a hash mismatch, write the correct hash into the target's `file` and check again. Needs `config`. See [Updating hashes](#updating-hashes). |

Installables follow the same rules as `nix build`: `.#web.pnpmDeps` resolves to `packages.<system>.web.pnpmDeps` or `legacyPackages.<system>.web.pnpmDeps`, and full attribute paths such as `.#checks.x86_64-linux.foo` also work. Relative flake references like `.` resolve against the workspace, not the config file. Lock files are not written.

Each installable must be a fixed-output derivation, such as `.#web.pnpmDeps` rather than `.#web`. The action fails on any other derivation, since rebuilding it verifies no hash.

## Config file

Each table in the config file is a target. The table name identifies the target, and these fields describe it:

| Field         | Required | Description                                                                     |
| ------------- | -------- | ------------------------------------------------------------------------------- |
| `installable` | yes      | Nix installable of the FOD.                                                     |
| `file`        | no       | File that declares the FOD's hash, relative to the workspace. Used by `update`. |

The action ignores other fields as well.

## Outputs

| Output      | Description                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------- |
| `key`       | SHA-256 over the check version, the current system, and the installables' derivation paths. |
| `cache-hit` | `true` if the check was skipped because a success for `key` was cached.                     |
| `updated`   | `true` if `update` wrote new hashes into the files of the targets.                          |

## Updating hashes

With `update: true`, a hash mismatch does not fail the check. The action replaces the declared hash in the target's `file` with the hash Nix got, then runs the whole check again on the updated files. If that passes, the step succeeds with `updated` set to `true`, and committing the change is up to the workflow. If it fails, the action restores the files and fails.

For example, to update Renovate pull requests with a GitHub App that can push to the repository:

```yaml
on:
  pull_request:

permissions:
  contents: read

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.head_ref }}
          persist-credentials: false
      - uses: NixOS/nix-installer-action@v1
      - id: fod
        uses: merrkry/fod-hash-check@v0.1.0
        with:
          # Only Renovate branches of this repository, never forks.
          update: ${{ github.event.pull_request.head.repo.full_name == github.repository && startsWith(github.head_ref, 'renovate/') }}
      # Created after the check, so the steps that build the pull request's
      # code never hold a token that can push.
      - id: app-token
        if: steps.fod.outputs.updated == 'true'
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.BOT_CLIENT_ID }}
          private-key: ${{ secrets.BOT_PRIVATE_KEY }}
      - if: steps.fod.outputs.updated == 'true'
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          APP_SLUG: ${{ steps.app-token.outputs.app-slug }}
        run: |
          user_id=$(gh api "/users/$APP_SLUG%5Bbot%5D" --jq .id)
          git config user.name "$APP_SLUG[bot]"
          git config user.email "$user_id+$APP_SLUG[bot]@users.noreply.github.com"
          git commit -am "Update FOD hashes"
          git push "https://x-access-token:$GH_TOKEN@github.com/$GITHUB_REPOSITORY.git" "HEAD:$GITHUB_HEAD_REF"
```

The app token matters: commits pushed with `GITHUB_TOKEN` start no workflow runs, so required checks on them would never report.

Renovate stops updating a branch once someone else commits to it. List the app's commit email in Renovate's [`gitIgnoredAuthors`](https://docs.renovatebot.com/configuration-options/#gitignoredauthors), so it keeps rebasing the pull request:

```json
{
  "gitIgnoredAuthors": ["<user-id>+<app-slug>[bot]@users.noreply.github.com"]
}
```

`<user-id>` is the ID of the app's bot user, from `https://api.github.com/users/<app-slug>%5Bbot%5D`.

### Known limitations

- The declared hash must appear literally in SRI form, such as `sha256-…`, exactly once across the targets' files, and belong to a single derivation. Otherwise the action fails and prints the correct hash, to be filled in by hand. This covers hashes written in other forms, computed hashes, and placeholders like `lib.fakeHash`.
- The hashes Nix got are read from the text of its hash mismatch errors, which Nix and Lix print the same way, but which is not a stable interface.
- An update run fetches the targets twice, since it checks again after updating. It saves no cache entry, so the next run checks the updated derivations once more.

## How it works

1. Evaluates all installables in one `nix derivation show`, fails if any of them has no fixed output hash, and hashes their derivation paths, together with the system and a check version, into `key`. Different spellings of the same derivations share a key. The Nix version and other tooling are not part of the key, since they do not change whether a declared hash is correct.
2. Looks up a cache entry for `key` without downloading it.
3. On a miss, or with `use-cache: false`, builds the evaluated derivations with `nix build --no-link` to make the outputs valid, then rebuilds those with valid outputs with `nix build --no-link --rebuild` to fetch them again and compare. Both builds run and use `--keep-going`, so one run reports every mismatch, whether it shows up in the build or only in the rebuild.
4. Saves the cache entry right after the check succeeds, so a later failing step in the job does not discard the result.

The marker file exists in the workspace only while it is being saved, so the action leaves the checkout unchanged.

## Prerequisites

- Nix with flakes enabled, installed by an earlier step, such as [NixOS/nix-installer-action](https://github.com/NixOS/nix-installer-action). The action does not install Nix.
- Credentials the fetches need, such as GitHub access tokens in `NIX_CONFIG`.
