{ config, ... }:
{
  nixosModules.defaults =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        boot.zfs.forceImportRoot = false;
        environment.enableAllTerminfo = true;
        networking.useNetworkd = true;
        services.resolved.enable = true;
        users.mutableUsers = false;
      }
      {
        networking.networkmanager = {
          enable = true;
          unmanaged = [
            "interface-name:enp*"
          ];
        };
      }
      {
        environment.systemPackages = with pkgs; [
          btop
          ethtool
        ];
      }
    ];
}
