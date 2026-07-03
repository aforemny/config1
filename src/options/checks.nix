{ lib, ... }:
{
  options.tests = lib.mkOption { type = lib.types.attrsOf lib.types.package; };
}
