{
  lib ? import "${sources.nixpkgs}/lib",
  sources ? import ./npins,
}:
let
  specialArgs = {
    inherit sources;
  };
  eval = lib.evalModules {
    modules =
      lib.filter (name: lib.hasSuffix ".nix" name) (
        lib.filesystem.listFilesRecursive (lib.cleanSource ./src)
      )
      ++ [
        {
          _asecret.PASSWORD_STORE_DIR = toString ./secrets;
        }
      ];
    inherit specialArgs;
  };
in
eval // specialArgs
