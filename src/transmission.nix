{ sources, ... }:
{
  systems.tower.modules = [
    "${sources.vpn-confinement}/modules/vpn-netns.nix"
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "t.nomath.org";
        ns = "tvpn";
        nsAddr = "192.168.15.1";
        bridgeAddr = "192.168.15.5";
        rpcPort = 9091;
        # Proton tunnel gateway (first tunnel address / DNS from the wg config).
        gateway = "10.2.0.1";
      in
      {
        age.secrets.transmission-wg.rekeyFile = toString ../secrets1/transmission-wg.age;

        vpnNamespaces.${ns} = {
          enable = true;
          wireguardConfigFile = config.age.secrets.transmission-wg.path;
          portMappings = [
            {
              from = rpcPort;
              to = rpcPort;
              protocol = "tcp";
            }
          ];
        };

        # Both services.babeld and VPN-Confinement enable IPv6 forwarding at
        # normal priority; sysctl values don't merge, so reconcile here (both
        # want it on).
        boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkForce 1;

        systemd.services.transmission.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };

        services.transmission = {
          enable = true;
          # Peer port is never opened on the host firewall: inbound connections
          # arrive over the tunnel. transmission-natpmp (below) leases the port
          # from Proton and opens it on the tunnel interface instead.
          openPeerPorts = false;
          openRPCPort = false;
          settings = {
            rpc-bind-address = nsAddr;
            rpc-port = rpcPort;
            rpc-whitelist-enabled = true;
            # nsAddr: transmission-natpmp reaches RPC from inside the namespace;
            # bridgeAddr: nginx / tremc reach it from the host.
            rpc-whitelist = "127.0.0.1,${nsAddr},${bridgeAddr}";
            # Terminated behind nginx (Host: ${fqdn}); the IP whitelist above and
            # the oauth2-proxy SSO layer are the access controls, so the
            # host-header guard would only get in the way.
            rpc-host-whitelist-enabled = false;
            # Public auth is enforced by nginx via oauth2-proxy (Keycloak SSO);
            # the RPC itself is not exposed outside the host.
            rpc-authentication-required = false;
            # transmission's own UPnP/NAT-PMP stays off; transmission-natpmp
            # drives the peer port explicitly (see below).
            port-forwarding-enabled = false;
            download-dir = "/srv/media/downloads";
            incomplete-dir = "/srv/media/downloads/.incomplete";
            umask = "002";
          };
        };
        systemd.services.transmission.unitConfig.RequiresMountsFor = [ "/srv/media" ];

        # Proton NAT-PMP dynamic port forwarding. Proton assigns an ephemeral
        # inbound port (its choice, ~60s lease) via NAT-PMP on the tunnel
        # gateway. Confined to the same namespace, this loop renews the lease,
        # opens that port on the tunnel interface (${ns}0), and points
        # transmission's advertised peer port at it so inbound peers can connect.
        # IPv4 only, matching Proton's port forwarding.
        systemd.services.transmission-natpmp = {
          description = "Proton NAT-PMP port forwarding for transmission";
          after = [ "transmission.service" ];
          wantedBy = [ "multi-user.target" ];
          vpnConfinement = {
            enable = true;
            vpnNamespace = ns;
          };
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = 10;
            # iptables inside the namespace needs NET_ADMIN; nothing else does.
            AmbientCapabilities = [ "CAP_NET_ADMIN" ];
            CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
            ExecStart = lib.getExe (
              pkgs.writeShellApplication {
                name = "transmission-natpmp";
                runtimeInputs = [
                  pkgs.libnatpmp
                  pkgs.iptables
                  config.services.transmission.package
                ];
                text = ''
                  gateway=${gateway}
                  rpc=${nsAddr}:${toString rpcPort}
                  wgif=${ns}0
                  fw_port=""

                  open_fw() {
                    iptables -I INPUT -i "$wgif" -p tcp --dport "$1" -j ACCEPT
                    iptables -I INPUT -i "$wgif" -p udp --dport "$1" -j ACCEPT
                  }
                  close_fw() {
                    iptables -D INPUT -i "$wgif" -p tcp --dport "$1" -j ACCEPT 2>/dev/null || true
                    iptables -D INPUT -i "$wgif" -p udp --dport "$1" -j ACCEPT 2>/dev/null || true
                  }
                  cleanup() { if [ -n "$fw_port" ]; then close_fw "$fw_port"; fi; }
                  trap cleanup EXIT

                  while :; do
                    # Renew both mappings; Proton assigns the same port to each.
                    if ! natpmpc -a 1 0 udp 60 -g "$gateway" >/dev/null 2>&1 \
                      || ! out=$(natpmpc -a 1 0 tcp 60 -g "$gateway" 2>/dev/null); then
                      echo "natpmpc request failed; retrying" >&2
                      sleep 5
                      continue
                    fi
                    port=$(printf '%s\n' "$out" \
                      | sed -nE 's/.*Mapped public port ([0-9]+).*/\1/p' | tail -n1)
                    if [ -z "$port" ]; then
                      echo "could not parse mapped port; retrying" >&2
                      sleep 5
                      continue
                    fi

                    # Reconcile the tunnel-interface firewall with the leased port.
                    if [ "$port" != "$fw_port" ]; then
                      echo "Proton forwarded port: $port (was: ''${fw_port:-none})" >&2
                      open_fw "$port"
                      old_port="$fw_port"
                      fw_port="$port"
                      if [ -n "$old_port" ]; then close_fw "$old_port"; fi
                    fi

                    # Keep transmission's peer port in sync (idempotent; re-applied
                    # each cycle so it survives a transmission restart).
                    transmission-remote "$rpc" -p "$port" >/dev/null \
                      || echo "could not set transmission peer port (retrying)" >&2

                    sleep 45
                  done
                '';
              }
            );
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://${nsAddr}:${toString rpcPort}";
              recommendedProxySettings = true;
            };
          };
        };

        security.acme = {
          acceptTerms = true;
          defaults.email = "aforemny@posteo.de";
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "t" ];

        environment.systemPackages = [ pkgs.tremc ];

        # /var/lib/transmission is its own ZFS dataset (zdata/local/transmission,
        # see platforms/tower.nix): bulk data on the raidz2 pool that survives the
        # rootfs rollback on its own, so it must NOT be persisted via impermanence.
        # Only ACME material still lives on /persist.
        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
