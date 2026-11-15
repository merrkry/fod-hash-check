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
          # Writes `content` to $out and declares the hash of `declared`.
          fod =
            {
              name,
              content,
              declared ? content,
            }:
            derivation {
              inherit name system content salt;
              builder = "/bin/sh";
              args = [
                "-c"
                ''printf %s "$content" > "$out"''
              ];
              outputHashMode = "flat";
              outputHashAlgo = "sha256";
              outputHash = builtins.hashString "sha256" declared;
            };
        in
        {
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
