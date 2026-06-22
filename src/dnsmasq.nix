{
  systems.apu.modules = [
    {
      services.resolved.enable = false;
      networking.nameservers = [ "127.0.0.1" ];
      services.dnsmasq = {
        enable = true;
        settings = {
          bind-interfaces = true;
          interface = "lan";
          dhcp-range = [
            "192.168.1.2,192.168.1.254"
            "::1,::400,constructor:lan,ra-names,12h"
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
        after = [ "sys-subsystem-net-devices-lan.device" ];
        requires = [ "sys-subsystem-net-devices-lan.device" ];
      };
      networking.firewall.interfaces.lan.allowedUDPPorts = [
        53 # DNS
        67 # DHCP
      ];
      networking.firewall.interfaces.lan.allowedTCPPorts = [
        53 # DNS
      ];
    }
  ];
}
