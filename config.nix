# Reads the targets from the TOML file in $CONFIG. `installables` and `files`
# list their installables and the files that declare their hashes, one per
# line.
let
  file = builtins.getEnv "CONFIG";
  targets = builtins.attrValues (
    builtins.mapAttrs (
      name: target:
      target
      // {
        installable = target.installable or (throw "${file}: target ${name} has no installable");
      }
    ) (builtins.fromTOML (builtins.readFile file))
  );
  lines = list: builtins.concatStringsSep "\n" list;
in
{
  installables = lines (map (target: target.installable) targets);
  # Each file once, since targets can share one.
  files = lines (
    builtins.attrNames (
      builtins.listToAttrs (
        map (target: {
          name = target.file;
          value = null;
        }) (builtins.filter (target: target ? file) targets)
      )
    )
  );
}
