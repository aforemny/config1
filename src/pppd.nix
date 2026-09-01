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
        # Software flow offload: after conntrack sees a flow established, its
        # packets take the flowtable fast path (neigh_xmit) instead of the full
        # routing+conntrack+PPPoE slow path, which is single-core-bound on this
        # 1 GHz GX-412TC. No `flags offload`: that is hardware offload,
        # unsupported by the igb NIC.
        #
        # The flowtable MUST list the real L2 ingress devices on both sides:
        # the `lan` bridge and the `wan` VLAN (802.1Q id 7 on enp4s0) that
        # carries the PPPoE session — NOT the `ppp0` pseudo-device. The offload
        # engine walks the netdev stack (`dev_fill_forward_path`) from the ppp0
        # egress route down through the pppoe layer to `wan`, recording the
        # PPPoE session id + VLAN tag + dest MAC, then transmits the fully
        # encapsulated frame directly on `wan`. Listing `ppp0` instead attaches
        # the fast path to an L3 point-to-point device that carries no L2/PPPoE
        # framing, so offloaded forwarded flows are mangled and collapse to
        # ~10 kB/s (kernel 6.18; see history of this file).
        # Only established flows are offloaded, so new inbound still traverses
        # the ip6 wan-inbound-filter (dns.nix); MSS clamp above runs on SYNs at
        # mangle priority and is never offloaded.
        networking.nftables.tables.flow-offload = {
          family = "inet";
          content = ''
            flowtable f {
              hook ingress priority filter
              devices = { lan, wan }
            }
            chain forward {
              type filter hook forward priority filter; policy accept;
              meta l4proto { tcp, udp } flow add @f
            }
          '';
        };
        # The build-time `nft --check` runs under LKL, where `lan`/`wan` do not
        # exist, so flowtable device resolution fails. Rewrite them to `lo` (the
        # one interface LKL always has) for the check only; the real ruleset the
        # service loads is unaffected.
        networking.nftables.preCheckRuleset = ''
          sed 's/devices = { lan, wan }/devices = { lo }/' -i ruleset.conf
        '';
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
        # WAN NIC (enp4s0) tuning for gigabit PPPoE. A single PPPoE session is
        # one outer flow, so the i211's hardware RSS cannot spread it — all WAN
        # RX lands on one core (~90% busy at 1 Gbit download). RPSCPUMask steers
        # in software, hashing the inner TCP flows across all 4 cores. Rx/Tx
        # BufferSize raise the ring from the 256 default toward the 4096 max to
        # absorb bursts on the slow CPU (fewer softirq time-squeezes). Matched by
        # OriginalName so the `wan` VLAN (same MAC) is not also caught.
        systemd.network.links."10-enp4s0" = {
          matchConfig.OriginalName = "enp4s0";
          linkConfig = {
            ReceivePacketSteeringCPUMask = "0-3";
            RxBufferSize = 1024;
            TxBufferSize = 1024;
          };
        };
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
