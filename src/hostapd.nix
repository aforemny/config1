{
  systems.apu.modules = [
    {
      services.hostapd = {
        enable = true;
        radios.wlp5s0 = {
          band = "5g";
          countryCode = "DE";
          wifi4.capabilities = [
            "HT40+"
            "LDPC"
            "SHORT-GI-20"
            "SHORT-GI-40"
            "TX-STBC"
            "RX-STBC1"
            "MAX-AMSDU-7935"
          ];
          wifi5 = {
            operatingChannelWidth = "80";
            capabilities = [
              "MAX-MPDU-11454"
              "RXLDPC"
              "SHORT-GI-80"
              "TX-STBC-2BY1"
              "RX-STBC-1"
              "RX-ANTENNA-PATTERN"
              "TX-ANTENNA-PATTERN"
              "MAX-A-MPDU-LEN-EXP7"
            ];
          };
          networks.wlp5s0 = {
            ssid = "apu";
            settings.bridge = "lan";
            authentication =
              let
                password = "my_sekret"; # TODO
              in
              {
                mode = "wpa3-sae-transition";
                saePasswords = [ { inherit password; } ];
                wpaPassword = password;
              };
          };
        };
      };
      systemd.services.hostapd = {
        after = [ "sys-subsystem-net-devices-lan.device" ];
        bindsTo = [ "sys-subsystem-net-devices-lan.device" ];
      };
      # hostapd adds wlp5s0 to the `lan` bridge once it enters AP/master mode.
      # facter declares every NIC with `useDHCP = true`, so turn that off here
      # (a bridge slave must not run its own DHCP client), and tell networkd to
      # keep the bridge membership hostapd sets up instead of detaching it.
      networking.interfaces.wlp5s0.useDHCP = false;
      systemd.network.networks."40-wlp5s0" = {
        matchConfig.Name = "wlp5s0";
        networkConfig.KeepMaster = true;
        linkConfig.RequiredForOnline = "no";
      };
    }
  ];
}
