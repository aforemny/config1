{ sources, ... }:
{
  nixosModules.colorscheme = {
    colorscheme = import "${sources.nix-colors}/schemes/materialtheme/material.nix";
  };
  _systems.defaultModules = [
    "${sources.nix-colors}/module"
  ];
}
