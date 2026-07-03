{ sources, ... }:
{
  # Headless Transmission on tower, confined to a Proton WireGuard tunnel via a
  # dedicated network namespace (VPN-Confinement). The namespace holds *only*
  # the wg interface + loopback and its default route is the tunnel, so the
  # daemon has no non-VPN interface to leak over: if the tunnel is down, peer
  # and tracker traffic simply has nowhere to go (killswitch by construction,
  # covering IPv4, IPv6, DHT/UDP and DNS uniformly).
  #
  # The RPC/WebUI is reached from the host default namespace over the veth
  # bridge (${nsAddr}), which is how nginx terminates TLS for the public
  # web UI and how a local tremc connects.
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
        fqdn = "transmission.nomath.org";
        ns = "tvpn";
        # VPN-Confinement bridge defaults: the namespace side of the veth
        # (where the daemon binds) and the host side (the source address the
        # host uses to reach it).
        nsAddr = "192.168.15.1";
        bridgeAddr = "192.168.15.5";
        rpcPort = 9091;
      in
      {
        # --- Secrets (agenix-rekey, master-encrypted sources under secrets1/) ---
        # The full wg-quick config (contains the private key); consumed at
        # runtime by the namespace-setup service, never copied into the store.
        age.secrets.transmission-wg.rekeyFile = toString ../secrets1/transmission-wg.age;
        # htpasswd file guarding the public web UI; read by nginx workers.
        age.secrets.transmission-htpasswd = {
          rekeyFile = toString ../secrets1/transmission-htpasswd.age;
          owner = config.services.nginx.user;
        };

        # --- VPN namespace (the killswitch) ---
        vpnNamespaces.${ns} = {
          enable = true;
          wireguardConfigFile = config.age.secrets.transmission-wg.path;
          # Opens ${toString rpcPort} on the namespace's veth INPUT chain so the
          # host (nginx / tremc) can reach the daemon at ${nsAddr}. The daemon's
          # peer traffic still egresses only via the tunnel.
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

        # --- Transmission, pinned into the VPN namespace ---
        systemd.services.transmission.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };

        services.transmission = {
          enable = true;
          # Peer port is not opened on the host firewall on purpose: inbound
          # connections would have to arrive over the tunnel. Proton dynamic
          # port forwarding (NAT-PMP) is a separate follow-up, so seeding is
          # outbound-biased for now.
          openPeerPorts = false;
          openRPCPort = false;
          settings = {
            # Bind RPC/WebUI to the namespace side of the veth; unreachable from
            # anywhere but the host bridge and the namespace itself.
            rpc-bind-address = nsAddr;
            rpc-port = rpcPort;
            # Only the host (nginx/tremc) and the namespace loopback may talk RPC.
            rpc-whitelist-enabled = true;
            rpc-whitelist = "127.0.0.1,${bridgeAddr}";
            # Terminated behind nginx (Host: ${fqdn}); the IP whitelist above and
            # nginx basic-auth are the access controls, so the host-header guard
            # would only get in the way.
            rpc-host-whitelist-enabled = false;
            # Public auth is enforced by nginx (basicAuthFile); the RPC itself is
            # not exposed outside the host.
            rpc-authentication-required = false;
            # No UPnP/NAT-PMP against the tunnel gateway (see openPeerPorts note).
            port-forwarding-enabled = false;
          };
        };

        # --- Public web UI over HTTPS, reachable from other devices ---
        # nginx sits in the host namespace and reverse-proxies to the daemon
        # across the veth bridge; TLS + basic-auth live entirely on the edge.
        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            basicAuthFile = config.age.secrets.transmission-htpasswd.path;
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

        # Published as ${fqdn} by src/dns.nix.
        dns.dynamicAAAA = [ "transmission" ];

        # Keyboard-driven local client (connects to ${nsAddr}:${toString rpcPort}).
        environment.systemPackages = [ pkgs.tremc ];

        # tower wipes / on boot; persist the daemon state (incl. Downloads) and
        # ACME material. The netns/veth are recreated each boot, so no state.
        state.directories = [
          "/var/lib/transmission"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
