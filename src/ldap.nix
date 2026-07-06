{
  systems.tower.modules = [
    (
      { config, ... }:
      let
        fqdn = "ldap.nomath.org";
        baseDn = "dc=nomath,dc=org";
        usersDn = "ou=people,${baseDn}";
        groupsDn = "ou=groups,${baseDn}";
        adminDn = "uid=admin,${usersDn}";
        ldapPort = 3890;
        httpPort = 17170;
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
            ldap_host = "127.0.0.1";
            ldap_port = ldapPort;
            http_host = "127.0.0.1";
            http_port = httpPort;
            http_url = "https://${fqdn}";
            ldap_user_email = "admin@nomath.org";
            ldap_user_pass_file = "/run/credentials/lldap.service/admin-pass";
            jwt_secret_file = "/run/credentials/lldap.service/jwt-secret";
            force_ldap_user_pass_reset = "always";
          };
        };

        systemd.services.lldap.serviceConfig.LoadCredential = [
          "admin-pass:${adminPasswordFile}"
          "jwt-secret:${jwtSecretFile}"
        ];

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

        # Publish ldap.nomath.org's AAAA so ACME (HTTP-01) can issue this
        # vhost's cert; every other public service registers its label the
        # same way (see src/dns.nix). Without it the order fails with NXDOMAIN.
        dns.dynamicAAAA = [ "ldap" ];

        services.keycloak.runtime = {
          ldap_user_federations.lldap = {
            realm = "nomath";
            enabled = true;
            connection_url = "ldap://127.0.0.1:${toString ldapPort}";
            users_dn = usersDn;
            bind_dn = adminDn;
            bind_credentialFile = adminPasswordFile;
            username_ldap_attribute = "uid";
            rdn_ldap_attribute = "uid";
            uuid_ldap_attribute = "uuid";
            user_object_classes = [ "person" ];
            edit_mode = "WRITABLE";
            import_enabled = true;
            search_scope = "SUBTREE";
          };

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

        state.directories = [
          # lldap now runs as DynamicUser=, so systemd keeps its StateDirectory
          # under /var/lib/private/lldap (with a /var/lib/lldap symlink). Persist
          # that real path, not the public symlink: persisting /var/lib/lldap
          # bind-mounts it, and on start systemd then tries to migrate the
          # pre-existing public dir to private -- a rename of a bind mount --
          # which fails with EBUSY (same reasoning as src/keycloak.nix).
          "/var/lib/private/lldap"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
