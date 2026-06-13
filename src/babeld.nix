{ config, ... }:
let
  inherit (config) systems;
in
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
      mkInterface = type: name: lib.nameValuePair name { inherit type; };
      localInterfaces = lib.listToAttrs (
        lib.map (mkInterface "wired") (wiredInterfaces ++ ethernetDongles)
        ++ lib.map (mkInterface "wireless") wirelessInterfaces
      );
      prefix = "fd42:1234:5678:90ab";
      inherit (pkgs.lib.mkIPv6 prefix config.networking.hostName "babel0") address prefixLength;
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
        networking.interfaces.lo.ipv6.addresses = [
          {
            address = address;
            inherit prefixLength;
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
        # Babel speaks only to directly-connected neighbors over IPv6
        # link-local (multicast ff02::1:6 / link-local unicast); never accept
        # protocol traffic from routable (e.g. public) source addresses.
        networking.firewall.extraInputRules = ''
          ip6 saddr fe80::/10 udp dport 6696 accept
        '';
      }
      # assign hostnames
      {
        networking.hosts = lib.mapAttrs' (
          name:
          { config, ... }:
          lib.nameValuePair "${(pkgs.lib.mkIPv6 prefix config.networking.hostName "babel0").address}" [
            config.networking.hostName
          ]
        ) systems;
      }
    ];
}
