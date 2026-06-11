{ config, ... }:
{
  nixosModules.defaults =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        boot.zfs.forceImportRoot = false;
        environment.enableAllTerminfo = true;
        networking.useNetworkd = true;
        services.resolved.enable = lib.mkDefault true;
        users.mutableUsers = false;
      }
      {
        networking.networkmanager = {
          enable = lib.mkDefault true;
          unmanaged = [
            "interface-name:enp*"
          ];
        };
      }
      {
        environment.systemPackages = with pkgs; [
          btop
          ethtool
          fio
          iw
          jq
          nm2nix
          python3
          wev
        ];
      }
      {
        systemd.services.systemd-networkd-wait-online.wantedBy = lib.mkForce [];
      }
    ];
}
