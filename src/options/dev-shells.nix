{ lib, pkgs, ... }:
{
  options.devShell = lib.mkOption {
    type = lib.types.raw;
    apply = defs: pkgs.mkShell defs;
    default = {};
  };
}
