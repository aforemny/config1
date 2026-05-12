{ lib, ... }:
{
  options.overlays = lib.mkOption {
    type = lib.types.attrsOf lib.types.deferredModule;
  };
}
