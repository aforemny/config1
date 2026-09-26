{ config, ... }:
{
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
          alsa-utils
          btop
          btop
          chromium
          csvkit
          ethtool
          feh
          file
          fio
          firefox
          ghc
          inetutils
          iw
          jq
          #libreoffice
          libreoffice
          mpv
          nixos-facter
          nm2nix
          pavucontrol
          python3
          silver-searcher-ng
          speedtest-cli
          tcpdump
          texliveFull
          usbutils
          wev
          wf-recorder
          wl-mirror
          zathura
          zbar
        ];
      }
      {
        systemd.services.systemd-networkd-wait-online.wantedBy = lib.mkForce [ ];
      }
    ];
}
