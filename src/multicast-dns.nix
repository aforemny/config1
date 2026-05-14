{
  nixosModules.multicast-dns =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      networkInterfaces = (
        lib.filter (unix_device_name: unix_device_name != "lo") (
          lib.concatMap (
            interface: interface.unix_device_names
          ) config.hardware.facter.report.hardware.network_interface
        )
      );
      lanInterfaces = lib.filter (lib.hasPrefix "enp") networkInterfaces;
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.hardware.facter.enable;
            message = "hardware `facter' must be enabled";
          }
          {
            assertion = config.services.resolved.enable;
            message = "service `resolved' must be enabled";
          }
          {
            assertion = config.networking.useNetworkd;
            message = "network must use networkd";
          }
        ];
        services.resolved = {
          settings.Resolve = {
            Cache = "no"; # caches wireless record
            LLMNR = "resolve";
            MulticastDNS = true;
          };
        };
        systemd.network.networks = lib.listToAttrs (
          lib.map (
            name:
            lib.nameValuePair "40-${name}" {
              matchConfig.Name = name;
              networkConfig = {
                LinkLocalAddressing = "ipv4"; # TODO https://sourceware.org/bugzilla/show_bug.cgi?id=14413
                LLMNR = false;
                MulticastDNS = true;
              };
            }
          ) lanInterfaces
        );
        networking.firewall.allowedUDPPorts = [ 5353 ];
        networking.getaddrinfo = {
          enable = true;
          precedence = {
            "::ffff:169.254.0.0/112" = 100;
          };
        };
      }
      {
        environment.systemPackages = with pkgs; [
          iproute2 # `ip mptcp`
          mptcpd # `mptcpize`
        ];
      }
    ];
}
