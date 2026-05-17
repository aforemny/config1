{ lib, ... }:
{
  options.homeManagerModules = lib.mkOption {
    type = lib.types.attrsOf lib.types.deferredModule;
    default = [ ];
  };
}
