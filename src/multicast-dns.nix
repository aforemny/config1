{
  nixosModules.multicast-dns =
    { config, lib, ... }:
    let
      networkInterfaces = (
        lib.filter (unix_device_name: unix_device_name != "lo") (
          lib.concatMap (
            interface: interface.unix_device_names
          ) config.hardware.facter.report.hardware.network_interface
        )
      );
      perInterfaceConfig = (
        name:
        lib.nameValuePair "40-${name}" {
          matchConfig.Name = name;
          networkConfig = {
            MulticastDNS = true;
            LLMNR = false;
          };
        }
      );
    in
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
          LLMNR = "resolve";
          MulticastDNS = "true";
        };
      };
      systemd.network.networks = lib.listToAttrs (lib.map perInterfaceConfig networkInterfaces);
      networking.firewall.allowedUDPPorts = [ 5353 ];
    };
}
