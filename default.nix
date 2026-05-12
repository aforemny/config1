{
  pkgs ? import sources.nixpkgs { },
  sources ? import ./npins,
}:
let
  inherit (pkgs) lib;
  specialArgs = {
    inherit
      lib
      pkgs
      sources
      ;
  };
in
lib.evalModules {
  modules = lib.filesystem.listFilesRecursive (lib.cleanSource ./src);
  inherit specialArgs;
}
// specialArgs
