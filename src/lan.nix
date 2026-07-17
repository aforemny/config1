{
  systems.apu.modules = [
    {
      # apu's first three Ethernet ports are bridged into `lan`. This way,
      # connected to one of them behaves exactly like connecting to the
      # wireless network.
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
      # IPv6 Prefix Delegation. RAs are sent by dnsmasq.
      systemd.network.networks."40-lan" = {
        matchConfig.Name = "lan";
        networkConfig = {
          DHCPPrefixDelegation = "yes";
          IPv6SendRA = false;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "no";
      };
    }
  ];
}
