{ config, ... }:
{
  nixosModules.defaults =
    { lib, ... }:
    {
      boot.zfs.forceImportRoot = false;
      networking.useNetworkd = true;
      services.resolved.enable = true;
      users.mutableUsers = false;
    };
}
