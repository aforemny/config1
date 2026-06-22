{
  systems.apu.modules = [
    {
      services.resolved.enable = false;
      networking.nameservers = [ "127.0.0.1" ];
      services.dnsmasq = {
        enable = true;
        settings = {
          bind-interfaces = true;
          interface = "wlp5s0";
          dhcp-range = [
            "192.168.1.2,192.168.1.254"
            "::1,::400,constructor:wlp5s0,ra-names,12h"
          ];
          dhcp-option = [ "option6:dns-server,[::]" ];
          enable-ra = true;
          server = [
            "8.8.8.8"
            "8.8.4.4"
          ];
          domain-needed = true;
          bogus-priv = true;
        };
      };
      systemd.services.dnsmasq = {
        after = [ "sys-subsystem-net-devices-wlp5s0.device" ];
        requires = [ "sys-subsystem-net-devices-wlp5s0.device" ];
      };
      networking.firewall.interfaces.wlp5s0.allowedUDPPorts = [
        53 # DNS
        67 # DHCP
      ];
      networking.firewall.interfaces.wlp5s0.allowedTCPPorts = [
        53 # DNS
      ];
      networking.interfaces.wlp5s0.ipv4.addresses = [
        {
          address = "192.168.1.1";
          prefixLength = 24;
        }
      ];
    }
  ];
}
