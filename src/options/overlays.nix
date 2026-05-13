{ config, lib, pkgs, sources, ... }:
{
  options.overlays = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
  };
  config._module.args.pkgs = import "${sources.nixpkgs}" {
    overlays = lib.attrValues config.overlays;
  };
  config._module.args = {
    inherit (pkgs) lib;
  };
}
