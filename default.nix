{ lib ? import "${sources.nixpkgs}/lib"
, sources ? import ./npins
}:
lib.evalModules {
  modules = lib.filesystem.listFilesRecursive (lib.cleanSource ./src);
  specialArgs = {
    inherit sources lib;
  };
}
