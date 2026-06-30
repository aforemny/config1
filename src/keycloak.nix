{ sources, ... }:
{
  # Keycloak on tower, reachable at https://keycloak.nomath.org. nginx
  # terminates TLS and reverse-proxies to a loopback-only Keycloak; the
  # runtime layer (applicative-systems/declarative-runtime, keycloak branch)
  # reconciles realm state via OpenTofu after the service is up.
  systems.tower.modules = [
    "${sources.declarative-runtime}/services/keycloak/module.nix"
    (
      { config, ... }:
      let
        fqdn = "keycloak.nomath.org";
        # Keycloak's own HTTP listener: loopback only, nginx is the only client.
        httpPort = 8080;
        baseUrl = "http://127.0.0.1:${toString httpPort}";
        # Master-realm admin password. agenix-rekey generates a 48-char random
        # value, keeps it age-encrypted in the repo, and decrypts it at runtime
        # to a root-only file under /run/agenix -- never into the world-readable
        # nix store. Reused below for the first-boot seed and the runtime
        # service-account bootstrap so both speak the same credential.
        adminPasswordFile = config.age.secrets.keycloak-admin-password.path;
      in
      {
        age.secrets.keycloak-admin-password.generator.script = "alnum";
        age.secrets.keycloak-db-password.generator.script = "alnum";

        services.keycloak = {
          enable = true;

          # Local PostgreSQL (createLocally defaults true); password delivered
          # via systemd LoadCredential, never embedded in keycloak.conf.
          database.passwordFile = config.age.secrets.keycloak-db-password.path;

          settings = {
            hostname = "https://${fqdn}";
            http-enabled = true; # serve plain HTTP to nginx; TLS ends at nginx
            http-host = "127.0.0.1";
            http-port = httpPort;
            proxy-headers = "xforwarded"; # trust X-Forwarded-* from nginx
          };

          # Runtime reconciliation (the declarative-runtime pairing). With no
          # client credentials supplied it self-bootstraps a dedicated
          # service-account OIDC client from the master admin, then drives
          # OpenTofu against the live instance. Declare realm state under
          # services.keycloak.runtime.* (realms, clients, users, ...) as needed.
          runtime = {
            enable = true;
            inherit baseUrl;
            bootstrapAdminPasswordFile = adminPasswordFile;
          };
        };

        # Seed the master-realm `admin` user on first boot without leaking the
        # password into the store. services.keycloak.initialAdminPassword would
        # bake KC_BOOTSTRAP_ADMIN_PASSWORD into the world-readable keycloak.service
        # unit; instead we render an EnvironmentFile in tmpfs from the agenix
        # secret at runtime. KC_BOOTSTRAP_ADMIN_* is consumed only when no admin
        # exists yet, so it is harmless on later boots.
        systemd.services.keycloak-bootstrap-admin-env = {
          description = "Render Keycloak bootstrap-admin EnvironmentFile from the agenix secret";
          requiredBy = [ "keycloak.service" ];
          before = [ "keycloak.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            LoadCredential = [ "password:${adminPasswordFile}" ];
            RuntimeDirectory = "keycloak-bootstrap-admin";
            RuntimeDirectoryMode = "0700";
          };
          script = ''
            set -euo pipefail
            umask 077
            {
              printf 'KC_BOOTSTRAP_ADMIN_USERNAME=admin\n'
              printf 'KC_BOOTSTRAP_ADMIN_PASSWORD=%s\n' "$(cat "$CREDENTIALS_DIRECTORY/password")"
            } > "$RUNTIME_DIRECTORY/env"
          '';
        };
        systemd.services.keycloak.serviceConfig.EnvironmentFile = "/run/keycloak-bootstrap-admin/env";

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = baseUrl;
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

        # Published as keycloak.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "keycloak" ];

        # tower rolls / back on boot; everything stateful must be persisted.
        state.directories = [
          "/var/lib/postgresql" # keycloak's database
          "/var/lib/keycloak" # OpenTofu reconciler state
          "/var/lib/declarative-keycloak-bootstrap" # minted service-account client
          "/var/lib/acme" # TLS certificates
        ];
      }
    )
  ];
}
