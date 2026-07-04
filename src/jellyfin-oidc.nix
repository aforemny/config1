{
  # OIDC single sign-on for Jellyfin against the local Keycloak.
  #
  # Keycloak has no built-in Jellyfin support and Jellyfin has no built-in
  # OIDC, so this spans two halves that share one generated client secret:
  #
  #   * Keycloak side (fully declarative via the declarative-runtime pairing):
  #     a dedicated realm, a confidential `jellyfin` OIDC client, two realm
  #     roles, and a protocol mapper that surfaces realm roles in the ID token
  #     (the plugin reads the ID token first, then the access token as a
  #     fallback -- Keycloak only puts realm roles in the access token by
  #     default, so we add them to both).
  #
  #   * Jellyfin side (no NixOS/Terraform surface exists): the maintained
  #     `Ezeqielle/jellyfin-plugin-oidc` ("OIDC RBAC") v1.0.4 (targetAbi 10.11)
  #     is unpacked from its signed release and installed into the plugin dir,
  #     and its config XML (`Jellyfin.Plugin.OIDC.xml` -- Jellyfin derives the
  #     name from the assembly, see BasePlugin<T>.ConfigurationFileName) is
  #     rendered from the shared secret. A login button ("Sign in with
  #     Keycloak") is added via branding.xml.
  #
  #     Unlike the retired 9p4 plugin, OIDC RBAC keeps NO runtime state in its
  #     config file (SSO<->account links are matched by username against
  #     Jellyfin's user DB), so both the config and the branding are rendered
  #     authoritatively on every start -- the Nix definition is the single
  #     source of truth. Existing Jellyfin users (incl. those the old plugin
  #     created) are matched by username on first login, preserving watch state.
  #
  # Keycloak users need the `jellyfin-user` realm role for library access and
  # `jellyfin-admin` to become a Jellyfin administrator; the two RoleMappings
  # below translate those roles into Jellyfin permissions on every login.
  #
  # AUTHORIZATION NOTE: OIDC RBAC has no login-deny gate. Any `nomath`-realm
  # user who authenticates gets a Jellyfin account created (AutoCreateUsers)
  # and a session -- but with no matching RoleMapping and no DefaultRoleName
  # they land with Jellyfin's restrictive new-user defaults (EnableAllFolders
  # defaults false), i.e. an empty library. This is a soft-deny, weaker than
  # the old plugin's hard EnableAuthorization deny. Set AutoCreateUsers = false
  # (below) to refuse first-login provisioning entirely if a hard gate is
  # required (at the cost of pre-creating each Jellyfin user).
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
        # SSO-plugin provider key; appears in the OIDC Start/Callback paths.
        provider = "keycloak";
        jellyfinUrl = "https://jellyfin.nomath.org";
        keycloakRealmUrl = "https://keycloak.nomath.org/realms/${realm}";
        dataDir = config.services.jellyfin.dataDir;
        configDir = config.services.jellyfin.configDir;
        secretFile = config.age.secrets.jellyfin-oidc-client-secret.path;

        # Jellyfin names a BasePlugin<T> config file after the plugin assembly
        # (Path.ChangeExtension(AssemblyFileName, ".xml")); the release DLL is
        # Jellyfin.Plugin.OIDC.dll, so the file must be exactly this.
        pluginConfigFile = "Jellyfin.Plugin.OIDC.xml";

        # ABI-matched release (targetAbi 10.11.0.0 == Jellyfin 10.11.x).
        # `zip *.dll meta.json` puts every file at the zip root, hence
        # stripRoot = false (mirrors the Dockerfile `package` target).
        oidcPlugin = pkgs.fetchzip {
          url = "https://github.com/Ezeqielle/jellyfin-plugin-oidc/releases/download/v1.0.4/oidc-rbac.zip";
          hash = "sha256-kmEdwAeH28kclaLEgYDm86SeHmc+PoBl/BWVgwrtWmQ=";
          stripRoot = false;
        };

        # Plugin config seed. Element names/order mirror
        # Jellyfin.Plugin.OIDC.Configuration.PluginConfiguration (XmlSerializer
        # binds a sequence in declaration order). The secret is a placeholder
        # substituted at runtime so it never enters the world-readable store.
        # ServerBaseUrl pins the redirect_uri Jellyfin builds
        # (GetSmartApiUrl can otherwise resolve to 127.0.0.1:8096 behind nginx).
        oidcConfigTemplate = pkgs.writeText pluginConfigFile ''
          <?xml version="1.0" encoding="utf-8"?>
          <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <Providers>
              <OidcProviderConfig>
                <ProviderId>${provider}</ProviderId>
                <DisplayName>Keycloak</DisplayName>
                <Authority>${keycloakRealmUrl}</Authority>
                <ClientId>${clientId}</ClientId>
                <ClientSecret>@OIDC_SECRET@</ClientSecret>
                <Scopes>openid profile email</Scopes>
                <RoleClaim>realm_access.roles</RoleClaim>
                <UsernameClaim>preferred_username</UsernameClaim>
                <DisplayNameClaim>name</DisplayNameClaim>
                <Enabled>true</Enabled>
                <ButtonColor>#4285F4</ButtonColor>
                <ButtonIcon></ButtonIcon>
                <AdditionalParameters></AdditionalParameters>
                <ServerBaseUrl>${jellyfinUrl}</ServerBaseUrl>
              </OidcProviderConfig>
            </Providers>
            <RoleMappings>
              <RoleMapping>
                <RoleName>jellyfin-admin</RoleName>
                <IsAdmin>true</IsAdmin>
                <EnableAllLibraries>true</EnableAllLibraries>
                <LibraryIds />
                <LibraryNames />
                <EnableLiveTv>true</EnableLiveTv>
                <EnableLiveTvManagement>true</EnableLiveTvManagement>
                <EnableMediaPlayback>true</EnableMediaPlayback>
                <EnableRemoteAccess>true</EnableRemoteAccess>
                <EnableTranscoding>true</EnableTranscoding>
                <EnableContentDeletion>false</EnableContentDeletion>
                <EnableCollectionManagement>true</EnableCollectionManagement>
                <EnableSubtitleManagement>true</EnableSubtitleManagement>
                <Priority>100</Priority>
              </RoleMapping>
              <RoleMapping>
                <RoleName>jellyfin-user</RoleName>
                <IsAdmin>false</IsAdmin>
                <EnableAllLibraries>true</EnableAllLibraries>
                <LibraryIds />
                <LibraryNames />
                <EnableLiveTv>true</EnableLiveTv>
                <EnableLiveTvManagement>false</EnableLiveTvManagement>
                <EnableMediaPlayback>true</EnableMediaPlayback>
                <EnableRemoteAccess>true</EnableRemoteAccess>
                <EnableTranscoding>true</EnableTranscoding>
                <EnableContentDeletion>false</EnableContentDeletion>
                <EnableCollectionManagement>false</EnableCollectionManagement>
                <EnableSubtitleManagement>false</EnableSubtitleManagement>
                <Priority>10</Priority>
              </RoleMapping>
            </RoleMappings>
            <DefaultProvider>${provider}</DefaultProvider>
            <AutoCreateUsers>true</AutoCreateUsers>
            <DefaultRoleName></DefaultRoleName>
          </PluginConfiguration>
        '';

        # branding.xml is rendered declaratively so the SSO login button is
        # always present; BrandingOptions holds no runtime state. Element order
        # matches Jellyfin 10.11. LoginDisclaimer is HTML (XML-escaped) injected
        # into the login page; it links to the plugin's Start endpoint, which
        # 302-redirects the browser into the OIDC flow.
        brandingConfig = pkgs.writeText "branding.xml" ''
          <?xml version="1.0" encoding="utf-8"?>
          <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <LoginDisclaimer>&lt;a href="/sso/OIDC/Start/${provider}" class="raised block emby-button button-submit"&gt;Sign in with Keycloak&lt;/a&gt;</LoginDisclaimer>
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
            # Authorization-code flow (the plugin adds PKCE on top).
            standard_flow_enabled = true;
            # The plugin's OIDC callback; ServerBaseUrl above pins the origin so
            # this single URI always matches.
            valid_redirect_uris = [
              "${jellyfinUrl}/sso/OIDC/Callback/${provider}"
            ];
            web_origins = [ jellyfinUrl ];
          };

          # Realm roles live in `realm_access.roles`, which Keycloak only adds to
          # the access token by default; add them to the ID token too (the
          # plugin reads the ID token first, then falls back to the access
          # token). UserInfo is harmless extra coverage.
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

          # Remove the retired 9p4/jellyfin-plugin-sso install and its config.
          # The new plugin matches accounts by username (watch state preserved),
          # so the old SSO<->account links are unneeded; dropping SSO-Auth.xml
          # also clears the stale client secret it stored in plaintext.
          rm -rf "${dataDir}/plugins/sso-authentication"
          rm -f "${dataDir}/plugins/configurations/SSO-Auth.xml"

          # Install the OIDC RBAC plugin (fixed dir; meta.json carries the real
          # version). Re-synced every start so the pinned build is authoritative.
          plugin_dir="${dataDir}/plugins/oidc-rbac"
          rm -rf "$plugin_dir"
          mkdir -p "$plugin_dir"
          cp -r ${oidcPlugin}/. "$plugin_dir/"
          chmod -R u+rwX "$plugin_dir"

          # Render the plugin config authoritatively every start (no runtime
          # state lives here). It carries the client secret, so write it 0600
          # from the LoadCredential-provided value -- it never enters the store.
          conf_dir="${dataDir}/plugins/configurations"
          mkdir -p "$conf_dir"
          umask u=rw,g=,o=
          secret="$(cat "$CREDENTIALS_DIRECTORY/oidc-secret")"
          sed "s|@OIDC_SECRET@|$secret|" ${oidcConfigTemplate} > "$conf_dir/${pluginConfigFile}"

          # Manage branding declaratively so the SSO login button is always
          # present (no runtime state lives here either).
          install -D -m 0644 ${brandingConfig} "${configDir}/branding.xml"
        '';
      }
    )
  ];
}
