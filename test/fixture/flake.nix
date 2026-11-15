{
  outputs =
    { self }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # CI writes a per-run salt, so each run gets fresh derivations and
      # cache keys while output paths stay the same.
      salt = if builtins.pathExists ./salt then builtins.readFile ./salt else "";

      packagesFor =
        system:
        let
          # Writes `content` to $out.
          write =
            name: content: extra:
            derivation (
              {
                inherit
                  name
                  system
                  content
                  salt
                  ;
                builder = "/bin/sh";
                args = [
                  "-c"
                  ''printf %s "$content" > "$out"''
                ];
              }
              // extra
            );

          # Declares the hash of `declared` as its output hash.
          fod =
            {
              name,
              content,
              declared ? content,
            }:
            write name content {
              outputHashMode = "flat";
              outputHashAlgo = "sha256";
              outputHash = builtins.hashString "sha256" declared;
            };
        in
        {
          # Builds reproducibly, but has no hash to verify.
          package = write "fixture-package" "package" { };
          good = fod {
            name = "fixture-good";
            content = "good";
          };
          "app+web".deps = fod {
            name = "fixture-deps";
            content = "deps";
          };
          wrong = fod {
            name = "fixture-wrong";
            content = "actual";
            declared = "declared";
          };
          # Their hashes are declared literally in hashes.nix, for update.
          updatable = builtins.mapAttrs (
            name: hash:
            write "fixture-${name}" name {
              outputHashMode = "flat";
              outputHash = hash;
            }
          ) (import ./hashes.nix);
          # Same name and hash, so both have the same output path.
          stale-original = fod {
            name = "fixture-stale";
            content = "old";
          };
          stale = fod {
            name = "fixture-stale";
            content = "new";
            declared = "old";
          };
          # Like stale, with its hash declared literally in stale-hash.nix.
          stale-updatable = write "fixture-stale" "new" {
            outputHashMode = "flat";
            outputHash = import ./stale-hash.nix;
          };
        };
    in
    {
      packages = builtins.listToAttrs (
        map (system: {
          name = system;
          value = packagesFor system;
        }) systems
      );
    };
}
