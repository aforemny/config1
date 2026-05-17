{ config, lib, ... }:
{
  nixosModules.state = {
    options.state = {
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
      files = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
    };
  };
  homeManagerModules.state = {
    options.state = {
      directories = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
      files = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
    };
  };
}
