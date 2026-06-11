{ lib, ... }: {
  options.platforms = lib.mkOption { type = lib.types.attrsOf lib.types.deferredModule; };
}
