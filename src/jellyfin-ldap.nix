{
  # LDAP authentication for Jellyfin against the local lldap, with Keycloak kept
  # authoritative over the directory. This replaces the retired Keycloak OIDC
  # SSO plugin: Jellyfin no longer speaks OIDC at all, users sign in with the
  # native login form, and their credentials are checked directly against lldap.
  #
  # Two halves share this file:
  #
  #   * Keycloak side (declarative via the declarative-runtime pairing): the
  #     `nomath` realm and the managed user accounts. Keycloak remains the single
  #     source of truth for who exists and what their password is; the WRITABLE
  #     lldap federation (src/ldap.nix, sync_registrations = true) writes each
  #     account -- and the password the user sets during onboarding -- through to
  #     lldap, so lldap is the directory every consumer (mail, and now Jellyfin)
  #     authenticates against. No Jellyfin OIDC client or role/group scaffolding
  #     is defined anymore; Jellyfin authorization is handled on the Jellyfin
  #     side (see EnableAllFolders below), not via Keycloak realm roles.
  #
  #   * Jellyfin side (no NixOS/Terraform surface exists): the official
  #     `jellyfin/jellyfin-plugin-ldapauth` ("LDAP Authentication") v23
  #     (targetAbi 10.11.9) is unpacked from its signed release and installed
  #     into the plugin dir, and its config XML (`LDAP-Auth.xml` -- Jellyfin
  #     derives the name from the LDAP-Auth.dll assembly) is rendered from the
  #     shared lldap admin password (the search/bind account). The plugin binds
  #     as that account to locate the user, then re-binds as the user with the
  #     entered password to verify it.
  #
  #     The plugin's config is the single source of truth and is re-rendered
  #     authoritatively on every start. It keeps one piece of runtime state --
  #     the LdapUsers link table (lldap uid <-> Jellyfin user id) -- but that is
  #     a rebuildable cache: on login the plugin falls back to matching by
  #     username when the link is absent, so wiping it every start is non-fatal
  #     and preserves watch state. Existing Jellyfin accounts are matched by
  #     username (LdapUsernameAttribute = uid == the OIDC preferred_username), so
  #     accounts the old SSO plugin created keep their libraries and history.
  #
  # MIGRATION: accounts the OIDC plugin provisioned carry its
  # AuthenticationProviderId. LDAP-Auth only adopts accounts whose provider is
  # already its own, so without intervention the login form would try to
  # auto-create a duplicate and fail. preStart repoints those accounts' provider
  # to LDAP-Auth (idempotent, best-effort) so LDAP login claims them in place.
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
        dataDir = config.services.jellyfin.dataDir;
        configDir = config.services.jellyfin.configDir;

        # lldap coordinates (mirror src/ldap.nix). Jellyfin talks to lldap's
        # loopback LDAP listener in plaintext -- same trust boundary Keycloak's
        # federation already uses (ldap://127.0.0.1:3890).
        baseDn = "dc=nomath,dc=org";
        usersDn = "ou=people,${baseDn}";
        adminDn = "uid=admin,${usersDn}";
        ldapPort = 3890;
        # Search/bind account: the lldap admin. Its password already backs the
        # realm SMTP below and Keycloak's federation, so no new secret is minted.
        adminPasswordFile = config.age.secrets.lldap-admin-password.path;

        # IAuthenticationProvider FullNames. The OIDC value is what the retired
        # plugin stamped onto the accounts it created (UserSyncService.cs); the
        # LDAP value is what LDAP-Auth expects to own (GetType().FullName).
        oidcProvider = "Jellyfin.Plugin.OIDC.Auth.OidcAuthProvider";
        ldapProvider = "Jellyfin.Plugin.LDAP_Auth.LdapAuthenticationProviderPlugin";

        # Jellyfin names a BasePlugin<T> config file after the plugin assembly
        # (Path.ChangeExtension(AssemblyFileName, ".xml")); the release DLL is
        # LDAP-Auth.dll, so the file must be exactly this.
        pluginConfigFile = "LDAP-Auth.xml";

        # ABI-matched release (targetAbi 10.11.9.0, <= Jellyfin 10.11.11). The
        # official zip carries LDAP-Auth.dll, its Novell.Directory.Ldap runtime
        # dep, and meta.json at the zip root, hence stripRoot = false.
        ldapPlugin = pkgs.fetchzip {
          url = "https://github.com/jellyfin/jellyfin-plugin-ldapauth/releases/download/v23/ldap-authentication_23.0.0.0.zip";
          hash = "sha256-yuOAJTj+QKj6bxlJ+irDE2BjxH1ZbsgAri7fauDMOBM=";
          stripRoot = false;
        };

        # Plugin config seed. Element names/order mirror
        # Jellyfin.Plugin.LDAP_Auth.Config.PluginConfiguration. The bind password
        # is a placeholder substituted at runtime so it never enters the
        # world-readable store.
        #
        #   LdapSearchFilter ANDs with the entered-username match, so it gates
        #   *who may sign in*: any lldap person except the admin bind account
        #   (which is a service credential, and whose name would also collide
        #   with Jellyfin's local `admin`). Since Keycloak is the only writer of
        #   lldap accounts, this effectively means "a Keycloak-managed user".
        #   LdapUsernameAttribute = uid keeps the Jellyfin username equal to the
        #   OIDC preferred_username so pre-existing accounts are matched in place.
        #   EnableAllFolders grants library access on creation (parity with the
        #   old jellyfin-user role mapping). AllowPassChange stays false: lldap
        #   passwords are owned by Keycloak's onboarding flow, not Jellyfin.
        ldapConfigTemplate = pkgs.writeText pluginConfigFile ''
          <?xml version="1.0" encoding="utf-8"?>
          <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <LdapUsers />
            <LdapServer>127.0.0.1</LdapServer>
            <LdapPort>${toString ldapPort}</LdapPort>
            <UseSsl>false</UseSsl>
            <UseStartTls>false</UseStartTls>
            <SkipSslVerify>false</SkipSslVerify>
            <LdapBindUser>${adminDn}</LdapBindUser>
            <LdapBindPassword>@LDAP_BIND_PW@</LdapBindPassword>
            <LdapBaseDn>${usersDn}</LdapBaseDn>
            <LdapSearchFilter>(&amp;(objectClass=person)(!(uid=admin)))</LdapSearchFilter>
            <LdapAdminBaseDn></LdapAdminBaseDn>
            <LdapAdminFilter></LdapAdminFilter>
            <EnableLdapAdminFilterMemberUid>false</EnableLdapAdminFilterMemberUid>
            <LdapSearchAttributes>uid, mail</LdapSearchAttributes>
            <LdapClientCertPath></LdapClientCertPath>
            <LdapClientKeyPath></LdapClientKeyPath>
            <LdapRootCaPath></LdapRootCaPath>
            <CreateUsersFromLdap>true</CreateUsersFromLdap>
            <AllowPassChange>false</AllowPassChange>
            <LdapUidAttribute>uid</LdapUidAttribute>
            <LdapUsernameAttribute>uid</LdapUsernameAttribute>
            <LdapPasswordAttribute>userPassword</LdapPasswordAttribute>
            <EnableLdapProfileImageSync>false</EnableLdapProfileImageSync>
            <RemoveImagesNotInLdap>false</RemoveImagesNotInLdap>
            <LdapProfileImageAttribute>jpegPhoto</LdapProfileImageAttribute>
            <LdapProfileImageFormat>Default</LdapProfileImageFormat>
            <EnableAllFolders>true</EnableAllFolders>
            <EnabledFolders />
            <PasswordResetUrl></PasswordResetUrl>
          </PluginConfiguration>
        '';

        # branding.xml is rendered declaratively (no runtime state lives here) to
        # drop the "Sign in with Keycloak" disclaimer the OIDC setup injected --
        # its /sso/OIDC/Start link now 404s. The native login form drives LDAP
        # auth, so no button is needed. Element order matches Jellyfin 10.11.
        brandingConfig = pkgs.writeText "branding.xml" ''
          <?xml version="1.0" encoding="utf-8"?>
          <BrandingOptions xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <LoginDisclaimer></LoginDisclaimer>
            <CustomCss></CustomCss>
            <SplashscreenEnabled>false</SplashscreenEnabled>
          </BrandingOptions>
        '';
      in
      {
        # --- Keycloak side -------------------------------------------------
        # Keycloak-authoritative accounts, written through to lldap by the
        # WRITABLE federation (src/ldap.nix). Grant a new person by adding a
        # users.<name> entry; they can then sign in to Jellyfin against lldap.
        services.keycloak.runtime = {
          realms.${realm} = {
            enabled = true;
            display_name = "nomath.org";
            # Email-based onboarding for Keycloak-managed accounts: users are
            # created with no password and self-serve via "Forgot password".
            # Requires working outbound mail (SMTP below -> local maddy).
            reset_password_allowed = true;
            verify_email = true;
            login_with_email_allowed = true;
            smtp_server = {
              host = "mail.nomath.org";
              port = "587";
              starttls = true;
              from = "admin@nomath.org";
              from_display_name = "nomath.org";
              # maddy submission (587) authorizes the sender against the SASL
              # identity, so we auth+send as admin@nomath.org (its lldap
              # password); host must match the mail cert, hence mail.nomath.org.
              auth = {
                username = "admin@nomath.org";
                passwordFile = config.age.secrets.lldap-admin-password.path;
              };
            };
          };

          # Users are Keycloak-authoritative: declared here and written through
          # to lldap by the WRITABLE federation (src/ldap.nix), so lldap stays
          # the directory Jellyfin and mail consume. Each account is created with
          # a real email and no password; UPDATE_PASSWORD + VERIFY_EMAIL drive
          # onboarding over the realm SMTP above. The password the user sets lands
          # in lldap, which is what Jellyfin's LDAP login then verifies against.
          users.aforemny = {
            realm = realm;
            email = "aforemny@posteo.de";
            enabled = true;
            required_actions = [
              "UPDATE_PASSWORD"
              "VERIFY_EMAIL"
            ];
          };
          users.kirchner = {
            realm = realm;
            email = "kirchner@posteo.de";
            enabled = true;
            required_actions = [
              "UPDATE_PASSWORD"
              "VERIFY_EMAIL"
            ];
          };
        };

        # --- Jellyfin side -------------------------------------------------
        # preStart runs as the jellyfin user, before the server scans plugins,
        # with the lldap bind password exposed via LoadCredential= in
        # $CREDENTIALS_DIRECTORY.
        systemd.services.jellyfin.serviceConfig.LoadCredential = [
          "ldap-bind-pw:${adminPasswordFile}"
        ];
        systemd.services.jellyfin.preStart = lib.mkAfter ''
          set -euo pipefail

          # Remove the retired SSO plugins and their configs: the 9p4
          # jellyfin-plugin-sso and the Ezeqielle OIDC RBAC plugin. LDAP-Auth
          # matches accounts by username, so no per-plugin link state needs to
          # survive; dropping the config files also clears the client secrets
          # they stored in plaintext.
          rm -rf "${dataDir}/plugins/sso-authentication" "${dataDir}/plugins/oidc-rbac"
          rm -f "${dataDir}/plugins/configurations/SSO-Auth.xml" \
                "${dataDir}/plugins/configurations/Jellyfin.Plugin.OIDC.xml"

          # Adopt any accounts the OIDC plugin provisioned: repoint their auth
          # provider to LDAP-Auth so the LDAP login form claims them (matched by
          # username) with watch state intact, instead of erroring on a
          # duplicate-name auto-create. Idempotent; a no-op on a fresh server or
          # once migrated. preStart runs before the server, so the DB is not
          # locked. Best-effort: never fail startup over this.
          db="${dataDir}/data/jellyfin.db"
          if [ -f "$db" ]; then
            ${pkgs.sqlite}/bin/sqlite3 "$db" \
              "UPDATE Users SET AuthenticationProviderId = '${ldapProvider}' WHERE AuthenticationProviderId = '${oidcProvider}';" \
              || echo "jellyfin: OIDC->LDAP account migration skipped (non-fatal)" >&2
          fi

          # Install the LDAP-Auth plugin (fixed dir; meta.json carries the real
          # version). Re-synced every start so the pinned build is authoritative.
          plugin_dir="${dataDir}/plugins/ldap-auth"
          rm -rf "$plugin_dir"
          mkdir -p "$plugin_dir"
          cp -r ${ldapPlugin}/. "$plugin_dir/"
          chmod -R u+rwX "$plugin_dir"

          # Render the plugin config authoritatively every start. It carries the
          # LDAP bind password, so write it 0600 from the LoadCredential-provided
          # value -- it never enters the store. The LdapUsers link table is
          # rebuilt on next login by username match.
          conf_dir="${dataDir}/plugins/configurations"
          mkdir -p "$conf_dir"
          umask u=rw,g=,o=
          bind_pw="$(cat "$CREDENTIALS_DIRECTORY/ldap-bind-pw")"
          sed "s|@LDAP_BIND_PW@|$bind_pw|" ${ldapConfigTemplate} > "$conf_dir/${pluginConfigFile}"

          # Reset branding declaratively so the retired SSO login button is gone
          # (no runtime state lives here either).
          install -D -m 0644 ${brandingConfig} "${configDir}/branding.xml"
        '';
      }
    )
  ];
}
