{ config, ... }:
{
  nixosModules.defaults =
    { lib, pkgs, ... }:
    {
      boot.zfs.forceImportRoot = false;
      environment.systemPackages = with pkgs; [ btop ];
      networking.networkmanager.enable = true;
      networking.useNetworkd = true;
      services.resolved.enable = true;
      users.mutableUsers = false;
    };
}
