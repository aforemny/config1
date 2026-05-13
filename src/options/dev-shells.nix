{ lib, pkgs, ... }:
{
  options.devShell = lib.mkOption {
    type = lib.types.raw;
    apply = defs: pkgs.mkShell defs;
    default = {};
  };
  config.devShell.packages = with pkgs; [
    npins
    cake-cli
  ];
}
