{
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        systemd.services.set-hetzner-dns = {
          serviceConfig.LoadCredential = [
            "api-key:${pkgs.asecret-lib.password "nomath.org/hetzner-api-key"}"
          ];
          environment.CREDENTIALS_DIRECTORY = "%d";
          script = lib.getExe (
            pkgs.writeShellApplication {
              name = "set-hetzner-dns-script";
              text = ''
                set -x
                ip -6 addr show wlp5s0u1i2 |
                grep -i global |
                grep -Pv 'temporary|deprecated' |
                awk '{print $2}' |
                jq -R |
                jq -s 'map({ value: sub("/.*"; "") }) | { records : . }' |
                curl -fsS \
                  -H 'Authorization: Bearer '"$(cat "$CREDENTIALS_DIRECTORY"/api-key)" \
                  -H 'Content-Type: application/json' \
                  --data @- \
                  https://api.hetzner.cloud/v1/zones/nomath.org/rrsets/mc1/AAAA/actions/set_records
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
