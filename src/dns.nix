{ config, sources, ... }:
let
  zone = "nomath.org";
  towerDynamicA = config.systems.tower.config.dns.dynamicA;
  # Pinned by dnsmasq on apu (src/dnsmasq.nix).
  towerIPv4 = "192.168.1.7";

  # Keeps the `type` rrsets of `labels` pointed at this host's current
  # addresses. `discover` is a shell snippet that prints them, one per line.
  mkUpdater =
    {
      lib,
      pkgs,
      type,
      labels,
      discover,
    }:
    lib.getExe (
      pkgs.writeShellApplication {
        name = "set-hetzner-dns-${type}";
        text = ''
          discover() {
            ${discover}
          }
          # Current addresses as a JSON array of { value: ... }. A failing
          # discover fails the pipeline, and with it the script.
          addrs=$(
            discover |
            jq -R |
            jq -s 'map({ value: sub("/.*"; "") })'
          )
          addr_list=$(printf '%s' "$addrs" | jq -r 'map(.value) | join(", ")')
          if [ "$(printf '%s' "$addrs" | jq 'length')" -eq 0 ]; then
            echo "set-hetzner-dns: no ${type} address found; refusing to publish empty rrset" >&2
            exit 1
          fi
          echo "set-hetzner-dns: current ${type}: $addr_list"
          token="$(cat "$CREDENTIALS_DIRECTORY"/api-key)"
          base="https://api.hetzner.cloud/v1/zones/${zone}/rrsets"
          set_body=$(jq -n --argjson records "$addrs" '{ records: $records }')
          for name in ${lib.escapeShellArgs labels}; do
            # Replace the records if the rrset exists, otherwise create it.
            status=$(
              curl -sS -o /dev/null -w '%{http_code}' \
                -H "Authorization: Bearer $token" \
                "$base/$name/${type}"
            )
            case "$status" in
              200)
                curl -fsS -o /dev/null \
                  -H "Authorization: Bearer $token" \
                  -H 'Content-Type: application/json' \
                  --data "$set_body" \
                  "$base/$name/${type}/actions/set_records"
                echo "set-hetzner-dns: updated $name.${zone} ${type} -> $addr_list"
                ;;
              404)
                # Low TTL because the address is dynamic.
                create_body=$(jq -n --arg name "$name" --argjson records "$addrs" \
                  '{ name: $name, type: "${type}", ttl: 60, records: $records }')
                curl -fsS -o /dev/null \
                  -H "Authorization: Bearer $token" \
                  -H 'Content-Type: application/json' \
                  --data "$create_body" \
                  "$base"
                echo "set-hetzner-dns: created $name.${zone} ${type} -> $addr_list (ttl 60)"
                ;;
              *)
                echo "set-hetzner-dns: unexpected status $status for $name.${zone} ${type}" >&2
                exit 1
                ;;
            esac
          done
        '';
        runtimeInputs = with pkgs; [
          coreutils
          curl
          gawk
          gnugrep
          iproute2
          jq
        ];
        inheritPath = false;
        bashOptions = [
          "errexit"
          "noglob"
          "nounset"
          "pipefail"
        ];
      }
    );

  # oneshot, so that units ordered after it wait for the records.
  updaterService = hetznerApiKey: script: {
    serviceConfig.Type = "oneshot";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.LoadCredential = [ "api-key:${hetznerApiKey}" ];
    environment.CREDENTIALS_DIRECTORY = "%d";
    inherit script;
  };

  minutely = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "minutely";
      Unit = "set-hetzner-dns.service";
    };
  };
in
{
  # Declared on every host; a service that needs a public hostname adds its
  # label here, and the updater below (on tower) collects them via the module
  # system. See e.g. radicle.nix and minecraft-server.nix.
  nixosModules.dns =
    { lib, ... }:
    {
      options.dns.dynamicAAAA = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "radicle" ];
        description = ''
          Labels (relative to the nomath.org zone) whose AAAA record should be
          kept in sync with this host's current global IPv6 address.
        '';
      };
      options.dns.dynamicA = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "knot" ];
        description = ''
          Labels (relative to the nomath.org zone) whose A record should point
          at apu's public IPv4 address. Only tower's are published, since apu
          forwards ports to tower alone (see systems.apu.modules below). Most
          services stay IPv6-only; this is for those whose peers cannot reach
          IPv6, such as atproto relays.
        '';
      };
    };

  systems.tower.modules = [
    # Static DNS records provisioned declaratively via the declarative-runtime
    # hetzner-dns pairing (run-once OpenTofu against the Hetzner Cloud DNS API).
    # This COMPLEMENTS -- it does not replace -- the set-hetzner-dns updater
    # below: that updater keeps the *dynamic* per-host AAAA records in sync with
    # this box's rotating SLAAC address on a minutely timer, which a
    # build-time-rendered, run-once reconciler fundamentally cannot express.
    # Services declare their own static records under
    # services.hetzner-dns.runtime.{zone_rrsets,zone_records} (see src/maddy.nix).
    "${sources.declarative-runtime}/services/hetzner-dns/module.nix"
    (
      { config, ... }:
      {
        # Hetzner Cloud API token (DNS scope) for the nomath.org project; also
        # read by set-hetzner-dns below.
        age.secrets.hetzner-api-key.rekeyFile = ../secrets/nomath.org/hetzner-api-key.age;
        services.hetzner-dns.runtime = {
          enable = true;
          tokenFile = config.age.secrets.hetzner-api-key.path;
        };
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/declarative-hetzner-dns";
            user = "declarative-hetzner-dns";
            group = "declarative-hetzner-dns";
            mode = "0700";
          }
        ];
        # Not inferred by features/persistence.nix (no StateDirectory=).
        systemd.services.declarative-hetzner-dns.unitConfig.RequiresMountsFor = [
          "/var/lib/declarative-hetzner-dns"
        ];
      }
    )
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      lib.mkIf (config.dns.dynamicAAAA != [ ]) {
        systemd.services = {
          set-hetzner-dns = updaterService config.age.secrets.hetzner-api-key.path (mkUpdater {
            inherit lib pkgs;
            type = "AAAA";
            labels = config.dns.dynamicAAAA;
            # The WAN interface is determined dynamically from the default
            # IPv6 route rather than hardcoded: the USB WiFi adapter is
            # renamed by the kernel (e.g. wlp5s0u1i2 -> wlp0s29u1u2i2) when
            # it is moved to a different port, which would otherwise break
            # this updater.
            discover = ''
              interface=$(
                ip -6 route show default |
                awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
              )
              if [ -z "$interface" ]; then
                echo "no default IPv6 route; cannot determine WAN interface" >&2
                exit 1
              fi
              ip -6 addr show "$interface" |
                grep -i global |
                grep -Pv 'temporary|deprecated' |
                awk '{print $2}'
            '';
          });
        }
        # Let's Encrypt validates over DNS, so a certificate ordered before its
        # label's AAAA record exists fails (and the failure is cached for a
        # while). Order each label's certificate after the records are synced.
        // lib.listToAttrs (
          map (label: {
            name = "acme-order-renew-${label}.${zone}";
            value = {
              wants = [ "set-hetzner-dns.service" ];
              after = [ "set-hetzner-dns.service" ];
            };
          }) (lib.filter (label: config.security.acme.certs ? "${label}.${zone}") config.dns.dynamicAAAA)
        );
        systemd.timers.set-hetzner-dns = minutely;
      }
    )
    (
      { config, lib, ... }:
      lib.mkIf (config.dns.dynamicA != [ ]) {
        # Connections to an unknown name, or to the bare IPv4 address that
        # every scanner sweeps, get no site: an empty reply on 80, and no
        # TLS handshake on 443.
        services.nginx.virtualHosts."_" = {
          default = true;
          rejectSSL = true;
          locations."/".return = "444";
        };
      }
    )
  ];

  systems.apu.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      lib.mkIf (towerDynamicA != [ ]) {
        # IPv4 has one public address, on ppp0, so tower's IPv4-facing names
        # point here and their ports go on to tower. Only HTTP(S): 80 for the
        # redirect and ACME, 443 for the sites. SSH and the rest stay IPv6.
        networking.nat.forwardPorts =
          map
            (port: {
              proto = "tcp";
              sourcePort = port;
              destination = "${towerIPv4}:${toString port}";
            })
            [
              80
              443
            ];

        age.secrets.hetzner-api-key.rekeyFile = ../secrets/nomath.org/hetzner-api-key.age;
        systemd.services.set-hetzner-dns =
          updaterService config.age.secrets.hetzner-api-key.path
            (mkUpdater {
              inherit lib pkgs;
              type = "A";
              labels = towerDynamicA;
              discover = "ip -4 addr show dev ppp0 scope global | awk '$1 == \"inet\" {print $2}'";
            });
        systemd.timers.set-hetzner-dns = minutely;
      }
    )
    {
      networking.nftables.tables.wan-inbound-filter = {
        family = "ip6";
        content = ''
          chain forward {
            type filter hook forward priority filter; policy accept;

            # Replies to connections a client itself opened.
            iifname "ppp0" ct state { established, related } accept

            # Exception: tower is reachable from the public internet.
            # The delegated /56 rotates daily, so match tower by its
            # stable interface identifier (low 64 bits) only, which is
            # independent of the current prefix. tower pins this IID
            # (= lib.mkIPv6 _ "tower" "lan") on its side; see
            # systems/tower.nix.
            iifname "ppp0" ip6 daddr & ::ffff:ffff:ffff:ffff == ::be5f:f4ff:fe02:536e accept

            # Everything else new from the WAN: no other client behind
            # apu is reachable from the public internet.
            iifname "ppp0" drop
          }
        '';
      };
    }
  ];

}
