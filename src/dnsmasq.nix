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
            "::1,::400,constructor:lan,ra-names,1h"
          ];
          # The printer is a stationary IPP target, so pin its address: the
          # workstations' CUPS queues point at this literal rather than a
          # dnsmasq name, because single-label names do not resolve there
          # (systemd-resolved refuses single-label unicast DNS, and the
          # `applicative.internal` search domain sends bare names to Tailscale).
          dhcp-host = [ "04:0e:3c:82:ce:be,192.168.1.5,printer" ];
          dhcp-option = [ "option6:dns-server,[::]" ];
          enable-ra = true;
          ra-param = "lan,200,1800";
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
      state.directories = [ "/var/lib/dnsmasq" ];
    }
  ];
}
