{
  systems.apu.modules = [
    (
      { lib, pkgs, ... }:
      let
        username = "1und1/ui6870-442@online.de"; # TODO
        password = "7V9RRzam@"; # TODO
      in
      {
        systemd.network.networks."40-ppp0" = {
          matchConfig.Name = "ppp0";
          networkConfig = {
            DHCP = lib.mkForce "ipv6";
            DefaultRouteOnDevice = true;
            KeepConfiguration = "static";
          };
          dhcpV6Config = {
            PrefixDelegationHint = "::/56";
            WithoutRA = "solicit";
            UseAddress = false;
            UseDNS = false;
            UseNTP = false;
            UseHostname = false;
            UseDomains = false;
          };
        };
        networking.nftables.tables.mss-clamp = {
          family = "inet";
          content = ''
            chain forward {
              type filter hook forward priority mangle; policy accept;
              tcp flags syn / syn,rst tcp option maxseg size set rt mtu
            }
          '';
        };
        networking.nat = {
          enable = true;
          externalInterface = "ppp0";
          internalInterfaces = [ "lan" ];
        };
        services.pppd = {
          enable = true;
          peers."1und1" = {
            autostart = true;
            enable = true;
            config = ''
              plugin pppoe.so wan

              nic-wan
              name "${username}"
              password "${password}"

              persist
              nodetach
              maxfail 0
              holdoff 5

              noipdefault
              defaultroute
              replacedefaultroute

              hide-password
              lcp-echo-interval 20
              lcp-echo-failure 3
              noauth
            '';
          };
        };
        systemd.services.pppd-1und1.unitConfig.StartLimitIntervalSec = 0;
        networking = {
          vlans.wan = {
            id = 7;
            interface = "enp4s0";
          };
          # bring up interface
          interfaces.wan = {
            useDHCP = false;
            ipv4.addresses = [ ];
          };
        };
        networking.interfaces.enp4s0.useDHCP = false;
        systemd.tmpfiles.rules = [ "f /etc/ppp/chap-secrets 0600 root root -" ];
        fileSystems."/etc/ppp/chap-secrets" = {
          device = pkgs.asecret-lib.password "isp/1und1/password";
          fsType = "auto";
          options = [
            "bind"
            "ro"
          ];
        };
      }
    )
  ];
}
