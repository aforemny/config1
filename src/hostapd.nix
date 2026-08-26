{ lib, ... }:
{
  systems =
    let
      # apu and ap advertise the exact same WiFi -- identical SSID, password
      # and roaming ESS -- each bridging its wireless NIC(s) into its local
      # `lan` bridge, so the two extend apu's single network.
      #
      # apu now runs a MediaTek MT7915 (PCI 14c3:7915, mt7915e). It is a DBDC
      # part that exposes 2.4 GHz and 5 GHz as two independent radios (wlan24
      # and wlan5), so apu serves both bands from a single hostapd instance.
      #
      # ap is still the single-band 5 GHz USB adapter (wlp0s16u1i2), which
      # needs an explicit channel (its adapter can't collect the survey data
      # ACS needs) and a reduced capability set (hostapd refuses to start if
      # told to advertise a capability the driver lacks).
      ssid = "apu";
      password = "my_sekret"; # TODO
      authentication = {
        mode = "wpa3-sae-transition";
        saePasswords = [ { inherit password; } ];
        wpaPassword = password;
      };

      # 802.11r Fast BSS Transition. apu (wlan24 + wlan5) and ap
      # (wlp0s16u1i2) share one SSID and this one mobility domain, so a client
      # fast-roams between any of the three BSSes with a 4-message FT exchange
      # instead of a full (re)association + SAE/4-way handshake -- that full
      # handshake is the "not fully connected to either" gap. Inter-AP key
      # distribution (RRB) rides the shared `lan` bridge that already joins apu
      # and ap at L2. Wildcard R0KH/R1KH entries let the three BSSes discover
      # each other dynamically with one shared key, so no per-BSS BSSID has to
      # be hard-coded here.
      mobilityDomain = "adc0"; # 2-octet MDID (hex); identical on every BSS
      ftKey = "7f1d6789d423984d1c4a249eabee0150e830a6cf3eb19337bf557c97ab66802f"; # 256-bit RRB key; TODO: move to a secret

      # Radio spec:
      #   { interface; band; channel; wifi4Capabilities;
      #     wifi5Capabilities ? null;   # null => no VHT (e.g. a 2.4 GHz radio)
      #     wifi5Width ? "80";          # VHT operating width ("20or40" | "80" | ...)
      #     radioSettings ? { }; }
      hostapd = radios: {
        services.hostapd = {
          enable = true;
          radios = lib.listToAttrs (
            map (
              r:
              lib.nameValuePair r.interface {
                inherit (r) channel band;
                countryCode = "DE";
                wifi4.capabilities = r.wifi4Capabilities;
                wifi5 =
                  if (r.wifi5Capabilities or null) == null then
                    { enable = false; }
                  else
                    {
                      operatingChannelWidth = r.wifi5Width or "80";
                      capabilities = r.wifi5Capabilities;
                    };
                settings = r.radioSettings or { };
                networks.${r.interface} = {
                  inherit ssid authentication;
                  settings = {
                    bridge = "lan";
                    # Advertise the FT AKMs alongside the transition-mode set the
                    # module computes; without these the client never attempts an
                    # FT roam. mkForce because the module hard-codes wpa_key_mgmt.
                    wpa_key_mgmt = lib.mkForce "WPA-PSK WPA-PSK-SHA256 SAE FT-PSK FT-SAE";
                    mobility_domain = mobilityDomain;
                    # R0KH-ID: unique per BSS. Interface names are unique across
                    # apu and ap, so they serve directly.
                    nas_identifier = r.interface;
                    ft_over_ds = 0; # over-the-air FT: widest client support
                    ft_psk_generate_local = 1; # PSK roams need no RRB round-trip
                    pmk_r1_push = 1;
                    # Wildcards: learn peer key holders over the bridge on demand.
                    r0kh = "ff:ff:ff:ff:ff:ff * ${ftKey}";
                    r1kh = "00:00:00:00:00:00 00:00:00:00:00:00 ${ftKey}";
                    # 802.11k/v: help the client discover and switch to the
                    # stronger AP promptly instead of clinging to a weak signal.
                    bss_transition = 1;
                    rrm_neighbor_report = 1;
                  };
                };
              }
            ) radios
          );
        };
        systemd.services.hostapd = {
          after = [ "sys-subsystem-net-devices-lan.device" ];
          bindsTo = [ "sys-subsystem-net-devices-lan.device" ];
        };
        # hostapd adds each radio to the `lan` bridge once it enters master mode.
        # facter declares every NIC with `useDHCP = true`, so turn that off here.
        # Also tell networkd to not detach the bridge membership.
        networking.interfaces = lib.listToAttrs (
          map (r: lib.nameValuePair r.interface { useDHCP = false; }) radios
        );
        systemd.network.networks = lib.listToAttrs (
          map (
            r:
            lib.nameValuePair "40-${r.interface}" {
              matchConfig.Name = r.interface;
              networkConfig.KeepMaster = true;
              linkConfig.RequiredForOnline = "no";
            }
          ) radios
        );
      };

      # MT7915 HT (WiFi 4) capabilities
      mt7915Wifi4 = [
        "HT40+"
        "LDPC"
        "SHORT-GI-20"
        "SHORT-GI-40"
        "TX-STBC"
        "RX-STBC1"
        "MAX-AMSDU-7935"
      ];
      # MT7915 5 GHz VHT (WiFi 5) capabilities
      mt7915Wifi5 = [
        "MAX-MPDU-7991"
        "RXLDPC"
        "SHORT-GI-80"
        "TX-STBC-2BY1"
        "RX-STBC-1"
        "SU-BEAMFORMER"
        "SU-BEAMFORMEE"
        "MU-BEAMFORMER"
        "RX-ANTENNA-PATTERN"
        "TX-ANTENNA-PATTERN"
        "MAX-A-MPDU-LEN-EXP7"
      ];
    in
    {
      apu.modules = [
        (hostapd [
          {
            interface = "wlan24";
            band = "2g";
            channel = 0;
            wifi4Capabilities = mt7915Wifi4;
          }
          {
            interface = "wlan5";
            band = "5g";
            # Different channel from ap (required: iOS rejects a same-SSID ESS
            # whose APs share a channel, and DE's single UNII-1 80 MHz block
            # can't hold two APs). ap keeps ch36 (HT40+ = 36+40); wlan5 takes
            # ch44 (HT40+ = 44+48). Two non-overlapping UNII-1 40 MHz channels,
            # both at the full 23 dBm, no DFS.
            channel = 44;
            wifi5Width = "20or40";
            wifi4Capabilities = mt7915Wifi4;
            wifi5Capabilities = mt7915Wifi5;
          }
        ])
        {
          # The radio exposes both NICs with the same PCI address.
          systemd.network.links = {
            "10-wlan24" = {
              matchConfig.PermanentMACAddress = "00:0a:52:0f:61:36";
              linkConfig.Name = "wlan24";
            };
            "10-wlan5" = {
              matchConfig.PermanentMACAddress = "00:0a:52:0f:61:37";
              linkConfig.Name = "wlan5";
            };
          };
        }
      ];
      ap.modules = [
        (hostapd [
          {
            interface = "wlp0s16u1i2";
            band = "5g";
            channel = 36;
            # 40 MHz (HT40+ = 36+40) so apu's wlan5 can take the adjacent ch44
            # (44+48) block: two non-overlapping UNII-1 channels rather than one
            # shared 80 MHz block, which iOS rejects for a same-SSID ESS.
            wifi5Width = "20or40";
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
          }
        ])
      ];
    };
}
