{
  nixosModules.hetzner-dns =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (config.networking.hostName == "tower") {
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
              curl -fsS \
                -H 'Authorization: Bearer '"$(cat "$CREDENTIALS_DIRECTORY"/api-key)" \
                -H 'Content-Type: application/json' \
                --data '{ "records": [ { "value": "198.51.100.2" } ] }' \
                https://api.hetzner.cloud/v1/zones/nomath.org/rrsets/mc1/A/actions/set_records
            '';
            runtimeInputs = with pkgs; [
              coreutils
              curl
            ];
            inheritPath = false;
          }
        );
      };
    };
}
