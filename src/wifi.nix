{
  nixosModules.wifi =
    { config, lib, ... }:
    lib.mkMerge [
      (lib.mkIf config.networking.networkmanager.enable {
        systemd.network.networks."10-wlan-unmanaged" = {
          matchConfig.Type = "wlan";
          linkConfig.Unmanaged = "yes";
        };
        # Connections added interactively (ensureProfiles' live in /run), and
        # NetworkManager's secret_key, which seeds stable-privacy IPv6
        # addresses and randomized MACs.
        state.directories = [
          "/etc/NetworkManager/system-connections"
          "/var/lib/NetworkManager"
        ];
        age.secrets = {
          wifi-apu-password.rekeyFile = ../secrets/wifi/apu.age;
          wifi-fritzbox-password.rekeyFile = ../secrets/wifi/fritzbox.age;
        };
        # The profiles' $WIFI_*_PSK references are filled in by envsubst, which
        # this script runs. Exported from the raw secrets, as hostapd shares
        # wifi-apu-password and can't read an environment file.
        systemd.services.NetworkManager-ensure-profiles = {
          serviceConfig.LoadCredential = [
            "wifi-apu:${config.age.secrets.wifi-apu-password.path}"
            "wifi-fritzbox:${config.age.secrets.wifi-fritzbox-password.path}"
          ];
          script = lib.mkBefore ''
            WIFI_APU_PSK=$(cat "$CREDENTIALS_DIRECTORY/wifi-apu")
            WIFI_FRITZBOX_PSK=$(cat "$CREDENTIALS_DIRECTORY/wifi-fritzbox")
            export WIFI_APU_PSK WIFI_FRITZBOX_PSK
          '';
        };
      })
      {
        networking.networkmanager.ensureProfiles.profiles = {
          "FRITZ!Box 7412" = {
            connection = {
              id = "FRITZ!Box 7412";
              type = "wifi";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              addr-gen-mode = "default";
              method = "auto";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "FRITZ!Box 7412";
            };
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk = "$WIFI_FRITZBOX_PSK";
            };
          };
          apu = {
            connection = {
              id = "apu";
              type = "wifi";
            };
            ipv4 = {
              method = "auto";
            };
            ipv6 = {
              addr-gen-mode = "default";
              method = "auto";
            };
            wifi = {
              mode = "infrastructure";
              ssid = "apu";
            };
            wifi-security = {
              key-mgmt = "sae";
              psk = "$WIFI_APU_PSK";
            };
          };
        };
      }
    ];
}
