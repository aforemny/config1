{
  # OIDC single sign-on for Jellyfin against the local Keycloak.
  #
  # Keycloak has no built-in Jellyfin support and Jellyfin has no built-in
  # OIDC, so this spans two halves that share one generated client secret:
  #
  #   * Keycloak side (fully declarative via the declarative-runtime pairing):
  #     a dedicated realm, a confidential `jellyfin` OIDC client, two realm
  #     roles, and a protocol mapper that surfaces realm roles in the ID token
  #     and UserInfo (Keycloak only puts them in the access token by default).
  #
  #   * Jellyfin side (no NixOS/Terraform surface exists): the archived but
  #     ABI-matched `9p4/jellyfin-plugin-sso` v4.0.0.4 (targetAbi 10.11) is
  #     unpacked from its signed release and installed into the plugin dir, and
  #     its `SSO-Auth.xml` is seeded once from the shared secret. It is seeded
  #     (not overwritten) because the plugin persists runtime state -- notably
  #     SSO<->Jellyfin account links -- back into that same file.
  #     A login button ("Sign in with Keycloak") is added declaratively via
  #     branding.xml, which is fully rendered (it carries no runtime state).
  #
  # Keycloak users need the `jellyfin-user` realm role to sign in and
  # `jellyfin-admin` to become a Jellyfin administrator.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        realm = "nomath";
        clientId = "jellyfin";
        # SSO-plugin provider key; appears in the OIDC callback path.
        provider = "keycloak";
        jellyfinUrl = "https://jellyfin.nomath.org";
        keycloakRealmUrl = "https://keycloak.nomath.org/realms/${realm}";
        dataDir = config.services.jellyfin.dataDir;
        configDir = config.services.jellyfin.configDir;
        secretFile = config.age.secrets.jellyfin-oidc-client-secret.path;

        # ABI-matched release (targetAbi 10.11.0.0 == Jellyfin 10.11.x).
        # Files (meta.json + DLLs) sit at the zip root, hence stripRoot = false.
        ssoPlugin = pkgs.fetchzip {
          url = "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v4.0.0.4/sso-authentication_4.0.0.4.zip";
          hash = "sha256-MJTyE6CeVLk7mlugauJ/F6bpi1kYwNtzNmQeH3+CFeQ=";
          stripRoot = false;
        };

        # SSO-Auth.xml seed. Element names/order mirror Jellyfin.Plugin.SSO_Auth
        # OidConfig (XmlSerializer is order-sensitive); the dictionary wrapper is
        # the stock pwelter34 item/key/value shape the plugin deserializes. The
        # secret is a placeholder substituted at runtime so it never enters the
        # world-readable store.
        ssoConfigTemplate = pkgs.writeText "SSO-Auth.xml" ''
          <?xml version="1.0" encoding="utf-8"?>
          <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <SamlConfigs />
            <OidConfigs>
              <item>
                <key>
                  <string>${provider}</string>
                </key>
                <value>
                  <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                    <OidEndpoint>${keycloakRealmUrl}</OidEndpoint>
                    <OidClientId>${clientId}</OidClientId>
                    <OidSecret>@OIDC_SECRET@</OidSecret>
                    <Enabled>true</Enabled>
                    <EnableAuthorization>true</EnableAuthorization>
                    <EnableAllFolders>true</EnableAllFolders>
                    <AdminRoles>
                      <string>jellyfin-admin</string>
                    </AdminRoles>
                    <Roles>
                      <string>jellyfin-user</string>
                    </Roles>
                    <EnableLiveTv>true</EnableLiveTv>
                    <RoleClaim>realm_access.roles</RoleClaim>
                    <OidScopes>
                      <string>email</string>
                    </OidScopes>
                    <NewPath>true</NewPath>
                  </PluginConfiguration>
                </value>
              </item>
            </OidConfigs>
          </PluginConfiguration>
        '';

        # branding.xml is rendered declaratively (not seeded) so the SSO login
        # button is always present; BrandingOptions holds no runtime state.
        # Element order matches Jellyfin 10.11. LoginDisclaimer is HTML
        # (XML-escaped) injected into the login page per the plugin README.
        brandingConfig = pkgs.writeText "branding.xml" ''
          <?xml version="1.0" encoding="utf-8"?>
          <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <LoginDisclaimer>&lt;form action="${jellyfinUrl}/sso/OID/start/${provider}"&gt;&lt;button class="raised block emby-button button-submit"&gt;Sign in with Keycloak&lt;/button&gt;&lt;/form&gt;</LoginDisclaimer>
            <CustomCss>a.raised.emby-button { padding: 0.9em 1em; color: inherit !important; } .disclaimerContainer { display: block; }</CustomCss>
            <SplashscreenEnabled>false</SplashscreenEnabled>
          </BrandingOptions>
        '';
      in
      {
        age.secrets.jellyfin-oidc-client-secret.generator.script = "alnum";

        # --- Keycloak side -------------------------------------------------
        services.keycloak.runtime = {
          realms.${realm} = {
            enabled = true;
            display_name = "nomath.org";
          };

          roles = {
            jellyfin-user = {
              realm = realm;
              description = "Allowed to sign in to Jellyfin.";
            };
            jellyfin-admin = {
              realm = realm;
              description = "Jellyfin administrator.";
            };
          };

          openid_clients.${clientId} = {
            realm = realm;
            name = "Jellyfin";
            access_type = "CONFIDENTIAL";
            # Shared secret: kept out of the store, rendered into the generated
            # OpenTofu config as a sensitive variable via LoadCredential=.
            client_secretFile = secretFile;
            standard_flow_enabled = true;
            # NewPath toggles redirect vs. legacy `r` path at login time; accept
            # both so either initiator works.
            valid_redirect_uris = [
              "${jellyfinUrl}/sso/OID/redirect/${provider}"
              "${jellyfinUrl}/sso/OID/r/${provider}"
            ];
            web_origins = [ jellyfinUrl ];
          };

          # Realm roles live in `realm_access.roles`, which Keycloak only adds to
          # the access token by default; the plugin reads the ID token/UserInfo.
          openid_user_realm_role_protocol_mappers.jellyfin-realm-roles = {
            realm = realm;
            client = clientId;
            claim_name = "realm_access.roles";
            multivalued = true;
            add_to_id_token = true;
            add_to_access_token = true;
            add_to_userinfo = true;
          };
        };

        # --- Jellyfin side -------------------------------------------------
        # preStart runs as the jellyfin user, before the server scans plugins,
        # with the secret exposed via LoadCredential= in $CREDENTIALS_DIRECTORY.
        systemd.services.jellyfin.serviceConfig.LoadCredential = [
          "oidc-secret:${secretFile}"
        ];
        systemd.services.jellyfin.preStart = lib.mkAfter ''
          set -euo pipefail

          # Install the SSO plugin (fixed dir; meta.json carries the real
          # version). Re-synced every start so the pinned build is authoritative.
          plugin_dir="${dataDir}/plugins/sso-authentication"
          rm -rf "$plugin_dir"
          mkdir -p "$plugin_dir"
          cp -r ${ssoPlugin}/. "$plugin_dir/"
          chmod -R u+rwX "$plugin_dir"

          # Seed the provider config once; never clobber (the plugin writes
          # account links back into this file).
          conf_dir="${dataDir}/plugins/configurations"
          mkdir -p "$conf_dir"
          if [ ! -e "$conf_dir/SSO-Auth.xml" ]; then
            umask u=rw,g=,o=
            secret="$(cat "$CREDENTIALS_DIRECTORY/oidc-secret")"
            sed "s|@OIDC_SECRET@|$secret|" ${ssoConfigTemplate} > "$conf_dir/SSO-Auth.xml"
          fi

          # Manage branding declaratively so the SSO login button is always
          # present (no runtime state lives here, unlike SSO-Auth.xml above).
          install -D -m 0644 ${brandingConfig} "${configDir}/branding.xml"
        '';
      }
    )
  ];
}
