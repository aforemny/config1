{ lib, ... }:
{
  options.nixosModules = lib.mkOption {
    type = lib.types.attrsOf lib.types.deferredModule;
  };
}
