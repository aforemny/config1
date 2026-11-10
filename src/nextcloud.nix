{
  # Nextcloud at https://cloud.nomath.org.
  #
  # AUTH. Browser logins go through Keycloak via the user_oidc app: every
  # `nomath` realm user gets an account on first login, named after their
  # preferred_username. The Keycloak group `admin` maps onto Nextcloud's admin
  # group of the same name (Nextcloud's name is fixed, hence not `admins`).
  # Desktop and mobile clients log in through the browser too and then use app
  # passwords. There is no local account; with Keycloak down, administer through
  # `ssh tower nextcloud-occ`.
  #
  # STATE. Files, config.php and appstore apps live in /var/lib/nextcloud on
  # /persist; the database is in the PostgreSQL that src/keycloak.nix persists.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "cloud.nomath.org";
        realm = "nomath";
        clientId = "nextcloud";
        adminGroup = "admin";
        clientSecretFile = config.age.secrets.nextcloud-oidc-client-secret.path;
      in
      {
        # alnum-nonl: Keycloak compares the client secret byte-for-byte (see
        # agenix-rekey.nix).
        age.secrets.nextcloud-oidc-client-secret.generator.script = "alnum-nonl";

        services.nextcloud = {
          enable = true;
          package = pkgs.nextcloud35;
          hostName = fqdn;
          https = true;
          maxUploadSize = "16G";
          configureRedis = true;
          database.createLocally = true;
          config.dbtype = "pgsql";
          settings = {
            default_phone_region = "DE";
            maintenance_window_start = 1; # UTC
            # Notifications go out through maddy on apostolforemny, as admin@nomath.org,
            # like Keycloak's mail (src/jellyfin-ldap.nix). An empty
            # mail_smtpsecure means STARTTLS on 587.
            mail_smtpmode = "smtp";
            mail_smtphost = "mail.nomath.org";
            mail_smtpport = 587;
            mail_smtpsecure = "";
            mail_smtpauth = true;
            mail_smtpname = "admin@nomath.org";
            mail_from_address = "admin";
            mail_domain = "nomath.org";
          };
          secrets.mail_smtppassword = config.age.secrets.maddy-admin-password.path;
          extraApps = { inherit (pkgs.nextcloud35Packages.apps) user_oidc; };
          # extraApps would otherwise turn the appstore off.
          appstoreEnable = true;
        };

        # user_oidc keeps its providers in the database and has no config.php
        # equivalent, so apply them through occ on every start. The command
        # upserts, and leaves anything it is not given alone.
        systemd.services.nextcloud-oidc-provider = {
          description = "Point Nextcloud's user_oidc app at Keycloak";
          wantedBy = [ "multi-user.target" ];
          requires = [ "nextcloud-setup.service" ];
          after = [ "nextcloud-setup.service" ];
          path = [ config.services.nextcloud.occ ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "nextcloud";
            # occ reads config.php, which reads services.nextcloud.secrets
            # from this unit's credentials too.
            LoadCredential = [
              "client-secret:${clientSecretFile}"
            ]
            ++ lib.mapAttrsToList (name: file: "${name}:${file}") config.services.nextcloud.secrets;
          };
          # unique-uid=0 keeps user ids and the group id readable, rather than
          # hashing them per provider; the group would not match `admin`
          # otherwise. allow_multiple_user_backends=0 sends the login page
          # straight to Keycloak.
          script = ''
            nextcloud-occ user_oidc:provider keycloak \
              --clientid=${clientId} \
              --clientsecret-file="$CREDENTIALS_DIRECTORY/client-secret" \
              --discoveryuri=https://keycloak.nomath.org/realms/${realm}/.well-known/openid-configuration \
              --unique-uid=0 \
              --mapping-uid=preferred_username \
              --group-provisioning=1 \
              --mapping-groups=groups \
              --group-whitelist-regex='/^${adminGroup}$/'
            nextcloud-occ config:app:set --type=string --value=0 user_oidc allow_multiple_user_backends
          '';
        };

        services.keycloak.runtime = {
          openid_clients.${clientId} = {
            inherit realm;
            enabled = true;
            access_type = "CONFIDENTIAL";
            standard_flow_enabled = true;
            valid_redirect_uris = [
              "https://${fqdn}/apps/user_oidc/code"
              "https://${fqdn}/index.php/apps/user_oidc/code"
            ];
            valid_post_logout_redirect_uris = [ "https://${fqdn}/*" ];
            web_origins = [ "https://${fqdn}" ];
            client_secretFile = clientSecretFile;
          };

          groups.${adminGroup} = {
            inherit realm;
            name = adminGroup;
            description = "Nextcloud administrators";
          };

          group_memberships.${adminGroup} = {
            inherit realm;
            group = adminGroup;
            members = [ "aforemny" ];
          };

          # Attached to the client directly, not through a client scope, so its
          # default scopes stay as they are.
          openid_group_membership_protocol_mappers.nextcloud-groups = {
            inherit realm;
            client = clientId;
            name = "groups";
            claim_name = "groups";
            full_path = false;
            add_to_id_token = true;
            add_to_access_token = true;
            add_to_userinfo = true;
          };
        };

        # The module brings the vhost; it only lacks TLS.
        services.nginx.virtualHosts.${fqdn} = {
          forceSSL = true;
          enableACME = true;
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Published as cloud.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "cloud" ];

        # Created via tmpfiles, not StateDirectory=, so a bare state.directories
        # string would be root:root (same reasoning as src/jellyfin.nix).
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/nextcloud";
            user = "nextcloud";
            group = "nextcloud";
            mode = "0750";
          }
        ];
        # Not inferred by features/persistence.nix (no StateDirectory=).
        systemd.services.nextcloud-cron.unitConfig.RequiresMountsFor = [ "/var/lib/nextcloud" ];
        systemd.services.nextcloud-setup.unitConfig.RequiresMountsFor = [ "/var/lib/nextcloud" ];
        systemd.services.nextcloud-update-db.unitConfig.RequiresMountsFor = [ "/var/lib/nextcloud" ];
        systemd.services.phpfpm-nextcloud.unitConfig.RequiresMountsFor = [ "/var/lib/nextcloud" ];

        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
