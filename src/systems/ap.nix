{
  systems.ap.modules = [
    {
      tags.graphical = false;
      networking = {
        networkmanager.enable = false;
        nftables.enable = true;
        hostId = "5aeff593";
        hostName = "ap";
      };
    }
    {
      # `ap` is a pure L2 access point, not a router: its only uplink is enp4s0
      # (patched into one of apu's LAN ports) and hostapd adds the WiFi BSS
      # (wlp0s16u1i2) to this same bridge once it reaches master mode (see
      # hostapd.nix). Wired uplink and wireless clients therefore share one L2
      # segment with apu's `lan`, so a WiFi client lands directly on apu's
      # subnet, DHCP pool and IPv6 prefix. ap does not route, NAT or serve
      # DHCP/DNS -- apu does all of that.
      networking.bridges.lan.interfaces = [ "enp4s0" ];
      # The bridge takes a management lease from apu's DHCP so ap is reachable on
      # the LAN by IPv4; link-local + babel (see babeld.nix) additionally make it
      # reachable fleet-wide at its babel0 address / `ap` hostname.
      systemd.network.networks."40-lan" = {
        matchConfig.Name = "lan";
        networkConfig = {
          DHCP = "yes";
          # Bring the bridge (and thus babel and hostapd's master) up at boot
          # without waiting for enp1s0 or the WiFi BSS to gain carrier.
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "no";
      };
    }
  ];
}
