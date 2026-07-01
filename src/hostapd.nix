{
  systems =
    let
      # apu and ap run the exact same WiFi -- identical SSID, password and radio
      # settings -- each bridging its own wireless NIC into its local `lan`
      # bridge, so the two form a single roaming ESS extending apu's network.
      # Keep this a shared definition, parameterised by the per-radio bits that
      # differ: interface name, channel, and HT/VHT capabilities. apu is the PCI
      # `wlp5s0` on ACS (channel 0) with the full Atheros capability set; ap is
      # the USB `wlp0s16u1i2`, which needs an explicit channel (its adapter
      # can't collect the survey data ACS needs) and a reduced capability set
      # (hostapd refuses to start if told to advertise a capability the driver
      # lacks) -- so there is one password to rotate and both APs stay in
      # lockstep.
      hostapd =
        {
          wifiInterface,
          channel,
          wifi4Capabilities ? [
            "HT40+"
            "LDPC"
            "SHORT-GI-20"
            "SHORT-GI-40"
            "TX-STBC"
            "RX-STBC1"
            "MAX-AMSDU-7935"
          ],
          wifi5Capabilities ? [
            "MAX-MPDU-11454"
            "RXLDPC"
            "SHORT-GI-80"
            "TX-STBC-2BY1"
            "RX-STBC-1"
            "RX-ANTENNA-PATTERN"
            "TX-ANTENNA-PATTERN"
            "MAX-A-MPDU-LEN-EXP7"
          ],
          radioSettings ? { },
        }:
        {
          services.hostapd = {
            enable = true;
            radios.${wifiInterface} = {
              inherit channel;
              band = "5g";
              countryCode = "DE";
              wifi4.capabilities = wifi4Capabilities;
              wifi5 = {
                operatingChannelWidth = "80";
                capabilities = wifi5Capabilities;
              };
              settings = radioSettings;
              networks.${wifiInterface} = {
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
          # hostapd adds the radio to the `lan` bridge once it enters AP/master mode.
          # facter declares every NIC with `useDHCP = true`, so turn that off here
          # (a bridge slave must not run its own DHCP client), and tell networkd to
          # keep the bridge membership hostapd sets up instead of detaching it.
          networking.interfaces.${wifiInterface}.useDHCP = false;
          systemd.network.networks."40-${wifiInterface}" = {
            matchConfig.Name = wifiInterface;
            networkConfig.KeepMaster = true;
            linkConfig.RequiredForOnline = "no";
          };
        };
    in
    {
      apu.modules = [
        (hostapd {
          wifiInterface = "wlp5s0";
          channel = 0;
        })
      ];
      ap.modules = [
        (hostapd {
          wifiInterface = "wlp0s16u1i2";
          channel = 36;
          # VHT 80 MHz on a fixed channel needs the 80 MHz segment centre; the
          # NixOS module emits vht_oper_chwidth but not this, so hostapd can't
          # locate the segment and aborts. 42 = centre channel of the 36-48 block.
          radioSettings = {
            vht_oper_centr_freq_seg0_idx = 42;
          };
          # ap's USB adapter supports fewer HT/VHT capabilities than apu's card;
          # advertising an unsupported one makes hostapd refuse to start.
          wifi4Capabilities = [
            "HT40+"
            "SHORT-GI-20"
            "SHORT-GI-40"
            "RX-STBC1"
            "MAX-AMSDU-7935"
          ];
          wifi5Capabilities = [
            "MAX-MPDU-11454"
            "SHORT-GI-80"
            "RX-STBC-1"
            "MAX-A-MPDU-LEN-EXP7"
          ];
        })
      ];
    };
}
