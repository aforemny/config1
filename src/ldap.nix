{
  # The shared account store. lldap is a small LDAP directory that is the single
  # source of truth for user accounts; two independent consumers bind against
  # it, which is the whole point of the "shared LDAP" approach:
  #
  #   * maddy (src/maddy.nix) verifies mail logins directly over LDAP.
  #   * Keycloak federates its `nomath` realm from it (the runtime block below),
  #     so every OIDC app already wired to Keycloak -- e.g. the Jellyfin SSO in
  #     src/jellyfin-oidc.nix -- authenticates these same accounts.
  #
  # Individual users, groups and password resets are managed through lldap's own
  # web UI at https://ldap.nomath.org; nothing per-user is declared in Nix.
  systems.tower.modules = [
    (
      { config, ... }:
      let
        fqdn = "ldap.nomath.org";
        baseDn = "dc=nomath,dc=org";
        usersDn = "ou=people,${baseDn}";
        groupsDn = "ou=groups,${baseDn}";
        # lldap's bootstrap admin, the only bind identity that exists
        # declaratively. Reused as the (read) bind account by maddy and by the
        # Keycloak federation below. A dedicated read-only bind user created in
        # the lldap UI (member of lldap_strict_readonly) would be the hardened
        # choice; swap both bind_dn values to it if you make one.
        adminDn = "uid=admin,${usersDn}";
        ldapPort = 3890;
        httpPort = 17170;
        # agenix-rekey generates these (48-char alnum), keeps them age-encrypted
        # in the repo and decrypts them at runtime to root-only files under
        # /run/agenix -- never into the world-readable nix store.
        adminPasswordFile = config.age.secrets.lldap-admin-password.path;
        jwtSecretFile = config.age.secrets.lldap-jwt-secret.path;
      in
      {
        age.secrets.lldap-admin-password.generator.script = "alnum";
        age.secrets.lldap-jwt-secret.generator.script = "alnum";

        services.lldap = {
          enable = true;
          settings = {
            ldap_base_dn = baseDn;
            # Loopback only: maddy, Keycloak and nginx are the only clients.
            ldap_host = "127.0.0.1";
            ldap_port = ldapPort;
            http_host = "127.0.0.1";
            http_port = httpPort;
            http_url = "https://${fqdn}";
            ldap_user_email = "admin@nomath.org";
            # Bootstrap admin password + JWT signing secret are handed over via
            # systemd credentials (below), not baked into lldap_config.toml.
            ldap_user_pass_file = "/run/credentials/lldap.service/admin-pass";
            jwt_secret_file = "/run/credentials/lldap.service/jwt-secret";
            # Keep the declared admin password authoritative across restarts.
            force_ldap_user_pass_reset = "always";
          };
        };

        # lldap runs as a DynamicUser and reads the two secrets as plain file
        # paths, so it cannot open the root-only agenix files itself. Hand them
        # over with systemd credentials: PID1 reads the agenix files and
        # re-exposes them under /run/credentials/lldap.service/ readable only by
        # the (dynamic) service user.
        systemd.services.lldap.serviceConfig.LoadCredential = [
          "admin-pass:${adminPasswordFile}"
          "jwt-secret:${jwtSecretFile}"
        ];

        # Admin web UI behind nginx + TLS, same shape as keycloak.nix / jellyfin.nix.
        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString httpPort}";
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

        # --- Keycloak side: federate the nomath realm from lldap -------------
        # The realm itself is declared in src/jellyfin-oidc.nix; here we only
        # attach the user federation and a group mapper. Keycloak's built-in
        # default mappers already map username<-uid, email<-mail, first/last
        # name<-givenName/sn, all of which lldap serves, so no attribute mappers
        # are needed. Attribute names / object classes below follow lldap's
        # documented Keycloak setup.
        services.keycloak.runtime = {
          ldap_user_federations.lldap = {
            realm = "nomath";
            enabled = true;
            connection_url = "ldap://127.0.0.1:${toString ldapPort}";
            users_dn = usersDn;
            bind_dn = adminDn;
            # Delivered as a sensitive OpenTofu variable via LoadCredential,
            # never written into the generated terraform config in the store.
            bind_credentialFile = adminPasswordFile;
            username_ldap_attribute = "uid";
            rdn_ldap_attribute = "uid";
            uuid_ldap_attribute = "uuid";
            user_object_classes = [ "person" ];
            edit_mode = "READ_ONLY"; # lldap is the source of truth
            import_enabled = true;
            search_scope = "SUBTREE";
          };

          # Bring lldap groups across so app access can be driven by group
          # membership: give a Keycloak group the `jellyfin-user` realm role
          # (src/jellyfin-oidc.nix) and every lldap member of the matching group
          # can sign in to Jellyfin.
          ldap_group_mappers.groups = {
            realm = "nomath";
            ldap_user_federation = "lldap";
            ldap_groups_dn = groupsDn;
            group_name_ldap_attribute = "cn";
            group_object_classes = [ "groupOfUniqueNames" ];
            membership_ldap_attribute = "member";
            membership_attribute_type = "DN";
            membership_user_ldap_attribute = "uid";
            memberof_ldap_attribute = "memberOf";
            mode = "READ_ONLY";
          };
        };

        # tower rolls / back on boot; everything stateful must be persisted.
        state.directories = [
          "/var/lib/lldap" # lldap's sqlite DB + derived server key
          "/var/lib/acme" # TLS certificates
        ];
      }
    )
  ];
}
