{ sources, ... }:
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
      { pkgs, ... }:
      {
        services.hetzner-dns.runtime = {
          enable = true;
          # The same Hetzner Cloud API token the AAAA updater uses (DNS scope),
          # read via systemd LoadCredential -- never copied into the store.
          tokenFile = pkgs.asecret-lib.password "nomath.org/hetzner-api-key";
        };
      }
    )
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        zone = "nomath.org";
      in
      lib.mkIf (config.dns.dynamicAAAA != [ ]) {
        systemd.services.set-hetzner-dns = {
          serviceConfig.LoadCredential = [
            "api-key:${pkgs.asecret-lib.password "${zone}/hetzner-api-key"}"
          ];
          environment.CREDENTIALS_DIRECTORY = "%d";
          script = lib.getExe (
            pkgs.writeShellApplication {
              name = "set-hetzner-dns-script";
              text = ''
                # The WAN interface is determined dynamically from the default
                # IPv6 route rather than hardcoded: the USB WiFi adapter is
                # renamed by the kernel (e.g. wlp5s0u1i2 -> wlp0s29u1u2i2) when
                # it is moved to a different port, which would otherwise break
                # this updater.
                interface=$(
                  ip -6 route show default |
                  awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }'
                )
                if [ -z "$interface" ]; then
                  echo "no default IPv6 route; cannot determine WAN interface" >&2
                  exit 1
                fi
                echo "set-hetzner-dns: WAN interface $interface"
                # Current global IPv6 addresses as a JSON array of { value: ... }.
                addrs=$(
                  ip -6 addr show "$interface" |
                  grep -i global |
                  grep -Pv 'temporary|deprecated' |
                  awk '{print $2}' |
                  jq -R |
                  jq -s 'map({ value: sub("/.*"; "") })'
                )
                addr_list=$(printf '%s' "$addrs" | jq -r 'map(.value) | join(", ")')
                if [ "$(printf '%s' "$addrs" | jq 'length')" -eq 0 ]; then
                  echo "set-hetzner-dns: no global IPv6 address on $interface; refusing to publish empty rrset" >&2
                  exit 1
                fi
                echo "set-hetzner-dns: current global IPv6: $addr_list"
                token="$(cat "$CREDENTIALS_DIRECTORY"/api-key)"
                base="https://api.hetzner.cloud/v1/zones/${zone}/rrsets"
                set_body=$(jq -n --argjson records "$addrs" '{ records: $records }')
                for name in ${lib.escapeShellArgs config.dns.dynamicAAAA}; do
                  # Replace the records if the AAAA rrset exists, otherwise create it.
                  status=$(
                    curl -sS -o /dev/null -w '%{http_code}' \
                      -H "Authorization: Bearer $token" \
                      "$base/$name/AAAA"
                  )
                  case "$status" in
                    200)
                      curl -fsS -o /dev/null \
                        -H "Authorization: Bearer $token" \
                        -H 'Content-Type: application/json' \
                        --data "$set_body" \
                        "$base/$name/AAAA/actions/set_records"
                      echo "set-hetzner-dns: updated $name.${zone} AAAA -> $addr_list"
                      ;;
                    404)
                      # Low TTL because the address is dynamic.
                      create_body=$(jq -n --arg name "$name" --argjson records "$addrs" \
                        '{ name: $name, type: "AAAA", ttl: 60, records: $records }')
                      curl -fsS -o /dev/null \
                        -H "Authorization: Bearer $token" \
                        -H 'Content-Type: application/json' \
                        --data "$create_body" \
                        "$base"
                      echo "set-hetzner-dns: created $name.${zone} AAAA -> $addr_list (ttl 60)"
                      ;;
                    *)
                      echo "set-hetzner-dns: unexpected status $status for $name.${zone}" >&2
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
        };
        systemd.timers.set-hetzner-dns = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "minutely";
            Unit = "set-hetzner-dns.service";
          };
        };
      }
    )
  ];

  systems.apu.modules = [
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
