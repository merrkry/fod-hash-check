# Reads the targets from the TOML file in $CONFIG and returns their
# installables, one per line.
let
  file = builtins.getEnv "CONFIG";
  targets = builtins.fromTOML (builtins.readFile file);
  installable =
    name: target: target.installable or (throw "${file}: target ${name} has no installable");
in
builtins.concatStringsSep "\n" (builtins.attrValues (builtins.mapAttrs installable targets))
