{ lib, ... }:
{
  options._outPath = lib.mkOption {
    type = lib.types.path;
  };
}
