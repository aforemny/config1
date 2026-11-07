{ config, ... }:
{
  # Profiles/history of the browsers and viewers installed below.
  homeManagerModules.defaults =
    { osConfig, lib, ... }:
    lib.mkIf (osConfig.tags.graphical or false) {
      state.directories = [
        ".config/mozilla"
        ".local/share/zathura"
      ];
    };
  nixosModules.defaults =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        boot.zfs.forceImportRoot = false;
        environment.enableAllTerminfo = true;
        # Modern TLS everywhere nginx runs: TLSv1.2/1.3, strong ciphers, OCSP
        # stapling, hybrid-PQ key exchange. No effect on hosts without nginx.
        # NB: this does NOT add HSTS -- that still needs an explicit add_header.
        services.nginx.recommendedTlsSettings = true;
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
          acpi
          alsa-utils
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
          mpv
          nixos-facter
          nm2nix
          pavucontrol
          python3
          silver-searcher-ng
          speedtest-cli
          stress-ng
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
