{ config, ... }: {
  nixosModules.defaults =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        boot.zfs.forceImportRoot = false;
        environment.enableAllTerminfo = true;
        networking.nftables.enable = true;
        networking.useNetworkd = true;
        services.resolved.enable = lib.mkDefault true;
        users.mutableUsers = false;
      }
      {
        networking.networkmanager = {
          enable = lib.mkDefault true;
          unmanaged = [ "interface-name:enp*" ];
        };
      }
      {
        environment.systemPackages = with pkgs; [
          btop
          btop
          ethtool
          fio
          inetutils
          iw
          iw
          jq
          nixos-facter
          nm2nix
          python3
          speedtest-cli
          tcpdump
          usbutils
          wev
        ];
      }
      {
        systemd.services.systemd-networkd-wait-online.wantedBy = lib.mkForce [ ];
      }
    ];
}
