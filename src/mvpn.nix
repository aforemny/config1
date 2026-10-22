{ lib, sources, ... }:
let
  # Management VPN (mvpn). A WireGuard hub on tower, every other host a spoke
  # dialing it at mvpn.nomath.org (tower's dynamic AAAA, see src/dns.nix).
  # Each host's node exporter listens on its mvpn address only.
  #
  # Prometheus is confined (VPN-Confinement) to the `mvpn` namespace on tower,
  # whose tunnel is just another spoke of tower's own hub (endpoint
  # 127.0.0.1): it can reach the mvpn addresses and nothing else. Spokes route
  # only the hub and Prometheus over the tunnel, so they cannot reach each
  # other through it.
  #
  # Keys come from the `wireguard-key` generator (src/agenix-rekey.nix), which
  # commits the public half as secrets/generated/mvpn-<name>.pub. A new host
  # needs an address below, then `agenix generate && agenix rekey`.
  hub = "tower";
  addresses = {
    tower = "10.77.0.1";
    apu = "10.77.0.2";
    ap = "10.77.0.3";
    x1e = "10.77.0.4";
    m1 = "10.77.0.5";
    family = "10.77.0.6";
    prometheus = "10.77.0.254";
  };
  subnet = "10.77.0.0/24";
  hosts = lib.removeAttrs addresses [ "prometheus" ];
  spokes = lib.removeAttrs hosts [ hub ];
  publicKey = name: lib.fileContents ../secrets/generated/mvpn-${name}.pub;
  listenPort = 51821;
  nodeExporterPort = 9100;
  prometheusPort = 9090;
  # The mvpn netns' veth/bridge; distinct from tvpn's 192.168.15.0/24
  # (src/transmission.nix) and fd93:9701:1d00::/64.
  nsAddr = "192.168.16.1";
  bridgeAddr = "192.168.16.5";

  # Every host: its key, and the node exporter on its mvpn address.
  common =
    name:
    { config, ... }:
    {
      age.secrets."mvpn-${name}".generator.script = "wireguard-key";
      services.prometheus.exporters.node = {
        enable = true;
        # Failed units are the most telling metric of the lot.
        enabledCollectors = [ "systemd" ];
        listenAddress = addresses.${name};
        port = nodeExporterPort;
      };
      # The address appears only once networkd has brought the tunnel up; the
      # exporter's Restart=always retries the bind until then.
      systemd.services.prometheus-node-exporter = {
        after = [ "systemd-networkd.service" ];
        wants = [ "systemd-networkd.service" ];
      };
      networking.firewall.interfaces.mvpn.allowedTCPPorts = [ nodeExporterPort ];
    };

  spoke =
    name:
    { config, ... }:
    {
      networking.wireguard.interfaces.mvpn = {
        ips = [ "${addresses.${name}}/32" ];
        privateKeyFile = config.age.secrets."mvpn-${name}".path;
        # The hub's address is dynamic (1&1 renumbers); re-resolve it.
        dynamicEndpointRefreshSeconds = 300;
        peers = [
          {
            publicKey = publicKey hub;
            endpoint = "mvpn.nomath.org:${toString listenPort}";
            allowedIPs = [
              "${addresses.${hub}}/32"
              "${addresses.prometheus}/32"
            ];
            persistentKeepalive = 25;
          }
        ];
      };
    };
in
{
  systems =
    lib.mapAttrs (name: _: {
      modules = [
        (common name)
        (spoke name)
      ];
    }) spokes
    // {
      ${hub}.modules = [
        (common hub)
        "${sources.vpn-confinement}/modules/vpn-netns.nix"
        (
          {
            config,
            lib,
            pkgs,
            ...
          }:
          {
            age.secrets.mvpn-prometheus.generator.script = "wireguard-key";

            networking.wireguard.interfaces.mvpn = {
              ips = [ "${addresses.${hub}}/24" ];
              inherit listenPort;
              privateKeyFile = config.age.secrets."mvpn-${hub}".path;
              peers = lib.mapAttrsToList (name: address: {
                publicKey = publicKey name;
                allowedIPs = [ "${address}/32" ];
              }) (lib.removeAttrs addresses [ hub ]);
            };
            networking.firewall.allowedUDPPorts = [ listenPort ];
            dns.dynamicAAAA = [ "mvpn" ];

            vpnNamespaces.mvpn = {
              enable = true;
              namespaceAddress = nsAddr;
              bridgeAddress = bridgeAddr;
              namespaceAddressIPv6 = "fd93:9701:1d01::2";
              bridgeAddressIPv6 = "fd93:9701:1d01::1";
              wireguardConfigFile = "/run/mvpn-netns/wg.conf";
              # Grafana reaches Prometheus at ${nsAddr}:${toString prometheusPort}.
              portMappings = [
                {
                  from = prometheusPort;
                  to = prometheusPort;
                  protocol = "tcp";
                }
              ];
            };

            # VPN-Confinement wants a wg-quick file; render it from the agenix
            # key at runtime, so the private key never enters the store. DNS is
            # mandatory for VPN-Confinement but unused: targets are addresses.
            systemd.services.mvpn-netns-config = {
              description = "Render the mvpn namespace's WireGuard config";
              requiredBy = [ "mvpn.service" ];
              before = [ "mvpn.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                LoadCredential = [ "key:${config.age.secrets.mvpn-prometheus.path}" ];
                RuntimeDirectory = "mvpn-netns";
                RuntimeDirectoryMode = "0700";
              };
              script = ''
                set -euo pipefail
                umask 077
                cat > "$RUNTIME_DIRECTORY/wg.conf" <<EOF
                [Interface]
                PrivateKey = $(cat "$CREDENTIALS_DIRECTORY/key")
                Address = ${addresses.prometheus}/32
                DNS = ${addresses.${hub}}

                [Peer]
                PublicKey = ${publicKey hub}
                AllowedIPs = ${subnet}
                Endpoint = 127.0.0.1:${toString listenPort}
                PersistentKeepalive = 25
                EOF
              '';
            };

            systemd.services.prometheus.vpnConfinement = {
              enable = true;
              vpnNamespace = "mvpn";
            };

            services.prometheus = {
              enable = true;
              port = prometheusPort;
              globalConfig.scrape_interval = "30s";
              scrapeConfigs = [
                {
                  job_name = "node";
                  static_configs = lib.mapAttrsToList (name: address: {
                    targets = [ "${address}:${toString nodeExporterPort}" ];
                    labels.instance = name;
                  }) hosts;
                }
              ];
            };

            # The module creates its StateDirectory, so a bare string is fine.
            state.directories = [ "/var/lib/prometheus2" ];
          }
        )
      ];
    };
}
