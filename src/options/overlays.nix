{
  config,
  lib,
  sources,
  ...
}:
{
  options.overlays = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
  };
  config = {
    nixosModules.overlays = {
      nixpkgs.overlays = lib.attrValues config.overlays;
    };
    _module.args.pkgs = import "${sources.nixpkgs}" {
      overlays = lib.attrValues config.overlays;
    };
  };
}
