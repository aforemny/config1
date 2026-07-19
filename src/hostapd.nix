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

      # Radio spec:
      #   { interface; band; channel; wifi4Capabilities;
      #     wifi5Capabilities ? null;   # null => no VHT (e.g. a 2.4 GHz radio)
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
                      operatingChannelWidth = "80";
                      capabilities = r.wifi5Capabilities;
                    };
                settings = r.radioSettings or { };
                networks.${r.interface} = {
                  inherit ssid authentication;
                  settings.bridge = "lan";
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
            channel = 0;
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
            # VHT 80 MHz on a fixed channel needs the 80 MHz segment centre; the
            # NixOS module emits vht_oper_chwidth but not this, so hostapd can't
            # locate the segment and aborts. 42 = centre channel of the 36-48
            # block.
            radioSettings = {
              vht_oper_centr_freq_seg0_idx = 42;
            };
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
