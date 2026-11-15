# Applied to packages.<system> of the flake. Returns the key, followed by an
# installable for each derivation it covers, separated by spaces.
{
  version,
  system,
  attributes,
}:
packages:
let
  split = sep: s: builtins.filter builtins.isString (builtins.split sep s);
  names = builtins.filter (name: name != "") (split "[[:space:]]+" attributes);
  get =
    name:
    builtins.foldl' (
      set: attr: set.${attr} or (throw "packages.${system}.${name} does not exist")
    ) packages (split "\\." name);
  drvs = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = (get name).drvPath;
    }) names
  );
  key = builtins.hashString "sha256" (builtins.toJSON { inherit version system drvs; });
in
if drvs == { } then
  throw "attributes must list at least one attribute path"
else
  toString ([ key ] ++ map (drv: "${drv}^*") (builtins.attrValues drvs))
