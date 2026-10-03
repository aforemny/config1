{
  systems.tower.modules = [
    (
      { config, pkgs, ... }:
      let
        baseDn = "dc=nomath,dc=org";
        usersDn = "ou=people,${baseDn}";
        groupsDn = "ou=groups,${baseDn}";
        # uid=admin is the directory superuser (OpenLDAP rootDN). It needs no
        # real entry: Keycloak's federation and Jellyfin's plugin both bind as it
        # with adminPasswordFile and get unrestricted read/write, which the
        # WRITABLE federation requires.
        adminDn = "uid=admin,${usersDn}";
        ldapPort = 3890;
        dbDir = "/var/lib/openldap/data";
        # Shared directory-admin bind password. It is used verbatim as OpenLDAP's
        # olcRootPW (compared byte-for-byte against the value Keycloak/Jellyfin
        # bind with), so it MUST carry no trailing newline -- hence alnum-nonl,
        # not alnum. Historically named `lldap-*`; kept for continuity with its
        # existing consumers (src/jellyfin-ldap.nix).
        adminPasswordFile = config.age.secrets.lldap-admin-password.path;
        bootstrapLdif = pkgs.writeText "nomath-base.ldif" ''
          dn: ${baseDn}
          objectClass: top
          objectClass: dcObject
          objectClass: organization
          o: nomath
          dc: nomath

          dn: ${usersDn}
          objectClass: organizationalUnit
          ou: people

          dn: ${groupsDn}
          objectClass: organizationalUnit
          ou: groups
        '';
      in
      {
        # OpenLDAP replaces lldap. lldap only implemented LDAP password-modify,
        # so Keycloak's WRITABLE federation write-through (user add + mail/sn
        # Replace) failed with LDAP error 53 and Keycloak-managed accounts never
        # reached the directory. OpenLDAP accepts those writes, so lldap stays
        # the directory every consumer (Jellyfin, maddy) authenticates against.
        age.secrets.lldap-admin-password = {
          generator.script = "alnum-nonl";
          # slapd's ExecStartPre loads olcRootPW from this file via `file://`
          # running as the openldap user, so it must own it. Every other consumer
          # reads it through root-side LoadCredential, where ownership is moot.
          owner = config.services.openldap.user;
        };

        services.openldap = {
          enable = true;
          # Loopback only; the Keycloak federation, the Jellyfin plugin and the
          # bootstrap below all talk to 127.0.0.1:3890 (the port lldap used).
          urlList = [ "ldap://127.0.0.1:${toString ldapPort}/" ];
          settings = {
            attrs.olcLogLevel = [ "stats" ];
            children = {
              "cn=schema".includes = [
                "${pkgs.openldap}/etc/schema/core.ldif"
                "${pkgs.openldap}/etc/schema/cosine.ldif"
                "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
              ];
              "olcDatabase={1}mdb" = {
                attrs = {
                  objectClass = [
                    "olcDatabaseConfig"
                    "olcMdbConfig"
                  ];
                  olcDatabase = "{1}mdb";
                  olcDbDirectory = dbDir;
                  olcSuffix = baseDn;
                  olcRootDN = adminDn;
                  # `{ path = …; }` loads the value from the runtime secret via
                  # `olcRootPW:< file://…`, never into the nix store.
                  olcRootPW = {
                    path = adminPasswordFile;
                  };
                  olcDbIndex = [
                    "objectClass eq"
                    "uid pres,eq"
                    "cn pres,eq"
                    "mail pres,eq"
                    "entryUUID eq"
                  ];
                  olcAccess = [
                    # Simple-bind authentication reads the user's own hash
                    # (anonymous -> auth); nobody may read password hashes.
                    "{0}to attrs=userPassword by self write by anonymous auth by * none"
                    # Everything else is authenticated-read; rootDN (uid=admin)
                    # bypasses ACLs entirely, so Keycloak keeps full write access.
                    "{1}to * by self read by users read by * none"
                  ];
                };
              };
            };
          };
        };

        # Seed the suffix + OUs once. The mdb persists (unlike declarativeContents,
        # which wipes the DB every start and would discard the users Keycloak
        # writes), so this is idempotent: `ldapadd -c` skips entries that already
        # exist (LDAP error 68).
        systemd.services.openldap-bootstrap = {
          description = "Seed the nomath.org base DN and OUs in OpenLDAP";
          after = [ "openldap.service" ];
          requires = [ "openldap.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            LoadCredential = [ "admin-pw:${adminPasswordFile}" ];
          };
          script = ''
            pw="$(cat "$CREDENTIALS_DIRECTORY/admin-pw")"
            ${pkgs.openldap}/bin/ldapadd -c -x \
              -H ldap://127.0.0.1:${toString ldapPort} \
              -D ${adminDn} -w "$pw" \
              -f ${bootstrapLdif} || true
          '';
        };

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
            # OpenLDAP's server-assigned immutable id (lldap exposed `uuid`).
            uuid_ldap_attribute = "entryUUID";
            # inetOrgPerson so Keycloak may write `mail`; its `person` superclass
            # makes `sn` + `cn` mandatory on the create-time add -- satisfied by
            # the users' last names (-> sn) and the cn mapper below.
            user_object_classes = [
              "inetOrgPerson"
              "organizationalPerson"
              "person"
            ];
            edit_mode = "WRITABLE";
            sync_registrations = true;
            import_enabled = true;
            search_scope = "SUBTREE";
          };

          # person/inetOrgPerson require cn, but Keycloak's default mappers only
          # set it from the first name (empty -> " " for users without one). A
          # full-name mapper writes cn = "First Last" (falling back to whichever
          # name is present) and takes precedence, giving tidy, always-present
          # cns while still satisfying the schema's mandatory cn.
          ldap_full_name_mappers.cn = {
            realm = "nomath";
            ldap_user_federation = "lldap";
            ldap_full_name_attribute = "cn";
            write_only = true;
          };

          ldap_group_mappers.groups = {
            realm = "nomath";
            ldap_user_federation = "lldap";
            ldap_groups_dn = groupsDn;
            group_name_ldap_attribute = "cn";
            # OpenLDAP's groupOfNames carries membership on `member`
            # (groupOfUniqueNames would use uniqueMember).
            group_object_classes = [ "groupOfNames" ];
            membership_ldap_attribute = "member";
            membership_attribute_type = "DN";
            membership_user_ldap_attribute = "uid";
            memberof_ldap_attribute = "memberOf";
            mode = "READ_ONLY";
          };
        };

        # OpenLDAP keeps the directory under /var/lib/openldap via StateDirectory=
        # (systemd chowns it, so the bare-string /persist bind-mount self-heals).
        # The cn=config tree is regenerated from `settings` every boot, so only
        # the mdb data must survive tower's rootfs rollback.
        state.directories = [
          "/var/lib/openldap"
        ];
      }
    )
  ];
}
