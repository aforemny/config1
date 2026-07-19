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
      # apu's two USB Ethernet dongles are extra babel mesh links. They are in
      # no facter report, so they must be hard-coded -- but only on apu, else
      # they appear as phantom interfaces in every other host's babel config.
      ethernetDongles = lib.optionals (config.networking.hostName == "apu") [
        "enp44s0u1"
        "enp44s0u2"
      ];
      mkInterface = type: name: lib.nameValuePair name { inherit type; };
      # A physical interface enslaved to a bridge has no L3 of its own, so babel
      # must not run on it directly; it speaks on the bridge instead. A bridge is
      # a multi-access shared segment (and apu's also carries the WiFi AP, added
      # out-of-band by hostapd), so it is treated as wireless: split-horizon off
      # so routes learned from one client are relayed to the others.
      bridges = config.networking.bridges;
      # WiFi BSS interfaces that hostapd attaches to a bridge (the BSS name is the
      # interface name) are enslaved just like networkd bridge members.
      hostapdBridged = lib.concatLists (
        lib.mapAttrsToList (
          _: radio: lib.filter (bss: radio.networks.${bss}.settings ? bridge) (lib.attrNames radio.networks)
        ) config.services.hostapd.radios
      );
      enslaved = lib.concatMap (bridge: bridge.interfaces) (lib.attrValues bridges) ++ hostapdBridged;
      unenslaved = lib.filter (name: !(lib.elem name enslaved));
      wiredInterfaces = unenslaved (lib.filter (lib.hasPrefix "en") networkInterfaces);
      wirelessInterfaces = unenslaved (lib.filter (lib.hasPrefix "wl") networkInterfaces);
      bridgeInterfaces = lib.map (mkInterface "wireless") (lib.attrNames bridges);
      localInterfaces = lib.listToAttrs (
        lib.map (mkInterface "wired") (wiredInterfaces ++ unenslaved ethernetDongles)
        ++ lib.map (mkInterface "wireless") wirelessInterfaces
        ++ bridgeInterfaces
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
            # The kernel may otherwise prefer a GUA from the outgoing interface.
            install pref-src ${address}
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
