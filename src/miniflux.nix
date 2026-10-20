{
  # Miniflux -- minimalist RSS reader -- at https://rss.nomath.org.
  #
  # AUTH. Browser logins go through Keycloak via Miniflux's native OIDC
  # support (not oauth2-proxy): mobile/desktop clients use the Fever and
  # Google Reader APIs with per-user API credentials and cannot follow an OIDC
  # redirect, so the vhost must stay reachable without a proxy session.
  # OAUTH2_USER_CREATION lets any `nomath` realm user create their account on
  # first login; such accounts are not admins. The local `admin` account
  # (password below) is the break-glass/admin login -- promote others under
  # Settings -> Users, and read its password with
  #   ssh tower cat /run/agenix/miniflux-admin-credentials
  #
  # STATE. Miniflux itself is stateless (DynamicUser, no StateDirectory); all
  # data lives in its PostgreSQL database, and Postgres is already persisted
  # by src/keycloak.nix.
  systems.tower.modules = [
    (
      { config, ... }:
      let
        fqdn = "rss.nomath.org";
        port = 8090;
        realm = "nomath";
        clientId = "miniflux";
        callbackUrl = "https://${fqdn}/oauth2/oidc/callback";
        clientSecretFile = config.age.secrets.miniflux-oauth2-client-secret.path;
      in
      {
        age.secrets = {
          # alnum-nonl: Keycloak compares the client secret byte-for-byte (see
          # agenix-rekey.nix).
          miniflux-oauth2-client-secret.generator.script = "alnum-nonl";
          # EnvironmentFile for services.miniflux.adminCredentialsFile, consumed
          # by systemd (as root) before the DynamicUser service starts.
          miniflux-admin-credentials.generator.script =
            { pkgs, ... }:
            "printf 'ADMIN_USERNAME=admin\\nADMIN_PASSWORD=%s\\n' \"$(${pkgs.pwgen}/bin/pwgen -s 48 1)\"";
        };

        services.miniflux = {
          enable = true;
          adminCredentialsFile = config.age.secrets.miniflux-admin-credentials.path;
          config = {
            LISTEN_ADDR = "127.0.0.1:${toString port}";
            BASE_URL = "https://${fqdn}";
            OAUTH2_PROVIDER = "oidc";
            OAUTH2_OIDC_PROVIDER_NAME = "Keycloak";
            OAUTH2_OIDC_DISCOVERY_ENDPOINT = "https://keycloak.nomath.org/realms/${realm}";
            OAUTH2_CLIENT_ID = clientId;
            OAUTH2_CLIENT_SECRET_FILE = "/run/credentials/miniflux.service/oauth2-client-secret";
            OAUTH2_REDIRECT_URL = callbackUrl;
            OAUTH2_USER_CREATION = 1;
          };
        };

        # DynamicUser + PrivateUsers: hand the root-only agenix file in via a
        # credential instead of making it readable.
        systemd.services.miniflux.serviceConfig.LoadCredential = [
          "oauth2-client-secret:${clientSecretFile}"
        ];

        services.keycloak.runtime.openid_clients.${clientId} = {
          inherit realm;
          enabled = true;
          access_type = "CONFIDENTIAL";
          standard_flow_enabled = true;
          valid_redirect_uris = [ callbackUrl ];
          web_origins = [ "https://${fqdn}" ];
          client_secretFile = clientSecretFile;
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              recommendedProxySettings = true;
            };
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "rss" ];

        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
