{
  systems.tower.modules = [
    (
      { config, lib, ... }:
      let
        realm = "nomath";
        keycloakFqdn = "keycloak.nomath.org";
        fqdn = "oauth2.nomath.org";
        clientId = "oauth2-proxy";
        callbackUrl = "https://${fqdn}/oauth2/callback";
        clientSecretFile = config.age.secrets.oauth2-proxy-client-secret.path;
        protectedVhosts = [
          "t.nomath.org"
          "sonarr.nomath.org"
          "radarr.nomath.org"
          "prowlarr.nomath.org"
        ];
      in
      {
        age.secrets = {
          # alnum-nonl (not alnum): the value is sent verbatim as the OIDC
          # client_secret over HTTP Basic, so it must carry no trailing newline
          # (see agenix-rekey.nix).
          oauth2-proxy-client-secret.generator.script = "alnum-nonl";
          # oauth2-proxy needs a 16/24/32-byte cookie key; aes-cookie-secret
          # yields a 32-byte value as unpadded URL-safe base64 (see agenix-rekey.nix).
          oauth2-proxy-cookie-secret.generator.script = "aes-cookie-secret";
        };

        services.oauth2-proxy = {
          enable = true;
          provider = "keycloak-oidc";
          oidcIssuerUrl = "https://${keycloakFqdn}/realms/${realm}";
          clientID = clientId;
          inherit clientSecretFile;
          redirectURL = callbackUrl;
          email.domains = [ "*" ];
          setXauthrequest = true;
          reverseProxy = true;
          trustedProxyIP = [
            "127.0.0.1/32"
            "::1/128"
          ];
          cookie = {
            domain = ".nomath.org";
            secretFile = config.age.secrets.oauth2-proxy-cookie-secret.path;
          };
          extraConfig = {
            upstream = "static://202";
            whitelist-domain = ".nomath.org";
          };
        };

        services.oauth2-proxy.nginx = {
          domain = fqdn;
          virtualHosts = lib.genAttrs protectedVhosts (_: {
            allowed_groups = [ "admins" ];
          });
        };

        services.nginx = {
          enable = true;
          # oauth2-proxy packs the full Keycloak id/access/refresh tokens (plus
          # every realm role) into its session cookie, so the Set-Cookie on
          # /oauth2/callback and the Cookie header on each subsequent request
          # overflow nginx's default 8k header buffers -> "upstream sent too big
          # header" 502 at the callback. Enlarge the upstream response-header
          # buffers and the client request-header buffers so the oversized auth
          # cookies pass through.
          commonHttpConfig = ''
            proxy_buffer_size 32k;
            proxy_buffers 8 32k;
            proxy_busy_buffers_size 64k;
            large_client_header_buffers 8 32k;
          '';
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "oauth2" ];

        services.keycloak.runtime = {
          openid_clients.${clientId} = {
            inherit realm;
            enabled = true;
            access_type = "CONFIDENTIAL";
            standard_flow_enabled = true;
            valid_redirect_uris = [ callbackUrl ];
            web_origins = [ "https://${fqdn}" ];
            client_secretFile = clientSecretFile;
          };

          openid_group_membership_protocol_mappers.${clientId} = {
            inherit realm;
            client = clientId;
            claim_name = "groups";
            full_path = false;
            add_to_id_token = true;
            add_to_access_token = true;
            add_to_userinfo = true;
          };

          groups.admins = {
            inherit realm;
          };

          group_memberships.admins = {
            inherit realm;
            group = "admins";
            members = [
              "aforemny"
              "kirchner"
            ];
          };
        };
      }
    )
  ];
}
