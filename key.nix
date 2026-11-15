# Reads the output of `nix derivation show` from the file in $DERIVATIONS, and
# returns the key, followed by an installable for each derivation, separated by
# spaces.
let
  version = builtins.getEnv "CHECK_VERSION";
  shown = builtins.fromJSON (builtins.readFile (builtins.getEnv "DERIVATIONS"));
  # Newer Nix versions nest the derivations and key them by base name.
  drvs = shown.derivations or shown;
  path = name: if builtins.substring 0 1 name == "/" then name else "${builtins.storeDir}/${name}";
  isFixed = drv: builtins.all (output: output ? hash) (builtins.attrValues drv.outputs);
  notFixed = builtins.filter (name: !isFixed drvs.${name}) (builtins.attrNames drvs);
  paths = builtins.sort builtins.lessThan (map path (builtins.attrNames drvs));
  key = builtins.hashString "sha256" (
    builtins.concatStringsSep "\n" (
      [
        version
        builtins.currentSystem
      ]
      ++ paths
    )
  );
in
if notFixed != [ ] then
  throw ''
    these derivations have no fixed output hash, so rebuilding them verifies no hash:
      ${builtins.concatStringsSep "\n  " (map path notFixed)}''
else
  toString ([ key ] ++ map (path: "${path}^*") paths)
