{
  lib ? import "${sources.nixpkgs}/lib",
  sources ? import ./npins,
}:
let
  specialArgs = {
    inherit
      lib
      sources
      ;
  };
in
lib.evalModules {
  modules = lib.filesystem.listFilesRecursive (lib.cleanSource ./src);
  inherit specialArgs;
}
// specialArgs
