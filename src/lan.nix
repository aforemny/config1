{
  systems.apu.modules = [
    {
      # The three otherwise-unused Ethernet ports (enp4s0 carries the PPPoE WAN)
      # are bridged together into `lan`. The WiFi AP (wlp5s0) is added to this
      # same bridge by hostapd (see hostapd.nix) once it is in master mode, so
      # wired and wireless clients share one L2 segment, subnet, DHCP pool and
      # IPv6 prefix -- i.e. a wired client behaves exactly like a wireless one.
      networking.bridges.lan.interfaces = [
        "enp1s0"
        "enp2s0"
        "enp3s0"
      ];
      networking.interfaces.lan.ipv4.addresses = [
        {
          address = "192.168.1.1";
          prefixLength = 24;
        }
      ];
      # Carve a /64 out of the /56 delegated to ppp0 and advertise it on the
      # bridge (reaches both wired and wireless clients through the bridge).
      systemd.network.networks."40-lan" = {
        matchConfig.Name = "lan";
        networkConfig = {
          DHCPPrefixDelegation = "yes";
          IPv6SendRA = true;
          # Bring the gateway IP, RA and babel up at boot without waiting for a
          # bridge member (a LAN cable or the WiFi AP) to gain carrier.
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "no";
      };
    }
  ];
}
