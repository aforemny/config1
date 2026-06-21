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
                set -x
                records=$(
                  ip -6 addr show ${interface} |
                  grep -i global |
                  grep -Pv 'temporary|deprecated' |
                  awk '{print $2}' |
                  jq -R |
                  jq -s 'map({ value: sub("/.*"; "") }) | { records : . }'
                )
                for name in ${lib.escapeShellArgs config.dns.dynamicAAAA}; do
                  curl -fsS \
                    -H 'Authorization: Bearer '"$(cat "$CREDENTIALS_DIRECTORY"/api-key)" \
                    -H 'Content-Type: application/json' \
                    --data "$records" \
                    "https://api.hetzner.cloud/v1/zones/${zone}/rrsets/$name/AAAA/actions/set_records"
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
}
