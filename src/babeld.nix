{
  nixosModules.babeld =
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
      wiredInterfaces = lib.filter (lib.hasPrefix "en") networkInterfaces;
      wirelessInterfaces = lib.filter (lib.hasPrefix "wl") networkInterfaces;
      ethernetDongles = [
        "enp44s0u1"
        "enp44s0u2"
      ];
      mkInterface = type: name: lib.nameValuePair name { type = "wired"; };
      localInterfaces = lib.listToAttrs (
        lib.map (mkInterface "wired") (wiredInterfaces ++ ethernetDongles)
        ++ lib.map (mkInterface "wireless") wirelessInterfaces
      );
      address = if config.networking.hostName == "x1e" then "10.42.0.1" else "10.42.0.2"; # TODO
      prefixLength = 32;
    in
    lib.mkMerge [
      # depends on facter
      {
        assertions = [
          {
            assertion = config.hardware.facter.enable;
            message = "hardware `facter' must be enabled";
          }
        ];
      }
      # babeld
      {
        services.babeld = {
          enable = true;
          interfaceDefaults.split-horizon = "auto";
          interfaces = localInterfaces;
          extraConfig = ''
            local-port 33123
            redistribute local ip ${address}/${toString prefixLength} allow
            redistribute local deny
          '';
        };
        networking.interfaces.lo.ipv4.addresses = [
          {
            address = address;
            prefixLength = 32;
          }
        ];
      }
      # link local auto-configuration
      {
        systemd.network = {
          enable = true;
          networks = lib.mapAttrs' (
            name: _:
            lib.nameValuePair "40-${name}" {
              matchConfig.Name = name;
              networkConfig.LinkLocalAddressing = "yes";
            }
          ) localInterfaces;
        };
        networking.firewall.allowedUDPPorts = [ 6696 ];
      }
      # assign hostnames
      {
        networking.hosts = {
          # TODO
          "10.42.0.1" = [ "x1e" ];
          "10.42.0.2" = [ "tower" ];
        };
      }
    ];
}
