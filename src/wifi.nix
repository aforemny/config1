{
  nixosModules.wifi = {
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
          psk = "adinaandalex"; # TODO
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
          psk = "my_sekret"; # TODO
        };
      };
    };
  };
}
