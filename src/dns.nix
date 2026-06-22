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
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        zone = "nomath.org";
        interface = "wlp5s0u1i2";
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
                # Current global IPv6 addresses as a JSON array of { value: ... }.
                addrs=$(
                  ip -6 addr show ${interface} |
                  grep -i global |
                  grep -Pv 'temporary|deprecated' |
                  awk '{print $2}' |
                  jq -R |
                  jq -s 'map({ value: sub("/.*"; "") })'
                )
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
                      curl -fsS \
                        -H "Authorization: Bearer $token" \
                        -H 'Content-Type: application/json' \
                        --data "$set_body" \
                        "$base/$name/AAAA/actions/set_records"
                      ;;
                    404)
                      # Low TTL because the address is dynamic.
                      create_body=$(jq -n --arg name "$name" --argjson records "$addrs" \
                        '{ name: $name, type: "AAAA", ttl: 60, records: $records }')
                      curl -fsS \
                        -H "Authorization: Bearer $token" \
                        -H 'Content-Type: application/json' \
                        --data "$create_body" \
                        "$base"
                      ;;
                    *)
                      echo "unexpected status $status for $name.${zone}" >&2
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
            iifname "ppp0" ip6 daddr & ::ffff:ffff:ffff:ffff == ::5143:4fdf:f468:2801 accept

            # Everything else new from the WAN: no other client behind
            # apu is reachable from the public internet.
            iifname "ppp0" drop
          }
        '';
      };
    }
  ];

}
