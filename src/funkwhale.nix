{ sources, ... }:
{
  # Funkwhale -- federated music server -- at https://music.nomath.org.
  #
  # PACKAGING. Funkwhale is not in nixpkgs yet. The maintained packaging is
  # NixOS/nixpkgs#512046 (the NGI team moving ngipkgs' projects/Funkwhale into
  # nixpkgs; ngipkgs itself is stuck at 2.0.0-alpha.2), pinned here as
  # `nixpkgs-funkwhale` (the PR branch). Only funkwhale, its module and the
  # Typesense server come from that tree: the package needs python typesense
  # 2.x and server 30.x (nixpkgs#503394, #565154), which our main nixpkgs pin
  # predates. Once the PR is merged and the main pin carries it, drop the
  # import, the `package` overrides and the pin.
  #
  # AUTH. Logins bind against tower's OpenLDAP (src/ldap.nix) by uid, i.e. the
  # same username/password as everywhere else; Django creates the account on
  # first login. Not behind oauth2-proxy: federation (/federation, /.well-known)
  # and the Subsonic API (/rest) are called by machines that cannot follow an
  # OIDC redirect. LDAP users are not admins -- promote one once with
  #   ssh tower 'cd /var/lib/funkwhale && sudo -u funkwhale funkwhale-manage \
  #     shell -c "from funkwhale_api.users.models import User; \
  #     User.objects.filter(username=\"aforemny\").update(is_staff=True, is_superuser=True)"'
  # after that user has logged in once.
  #
  # LIBRARY. Music lives on zdata next to the rest of the media stack:
  #   /srv/media/library/music  MUSIC_DIRECTORY_PATH, the in-place library:
  #                             import with `funkwhale-manage import_files
  #                             <library-uuid> /srv/media/library/music
  #                             --recursive --noinput --in-place`
  #   /srv/media/funkwhale      MEDIA_ROOT: uploads, covers, avatars
  # Both are served by nginx directly (X-Accel via /_protected/), so nginx and
  # funkwhale join the shared `transmission` group (src/servarr.nix). Neither
  # unit runs PrivateUsers=, so a supplementary group is enough here.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "music.nomath.org";
        fwPkgs = import sources.nixpkgs-funkwhale { inherit (pkgs.stdenv.hostPlatform) system; };
        musicDir = "/srv/media/library/music";
        mediaDir = "/srv/media/funkwhale";
        typesensePort = 8108;
        ldapBaseDn = "dc=nomath,dc=org";
        funkwhaleUnits = [
          "funkwhale-setup"
          "funkwhale-server"
          "funkwhale-worker"
          "funkwhale-beat"
        ];
      in
      {
        imports = [
          "${sources.nixpkgs-funkwhale}/nixos/modules/services/web-apps/funkwhale.nix"
        ];

        # Shared by Typesense (its admin key) and Funkwhale (its client key).
        age.secrets.funkwhale-typesense-api-key.generator.script = "alnum-nonl";
        # Funkwhale's secretEnvironmentFile. Assembled at generation time from
        # its dependencies, so after rotating the typesense key or the shared
        # directory password run `agenix generate -f funkwhale-env` too. Read
        # both as systemd EnvironmentFile= and by funkwhale-manage via
        # `source` (as the funkwhale user), hence alphanumeric values only.
        age.secrets.funkwhale-env = {
          owner = "funkwhale";
          generator = {
            dependencies = {
              typesense = config.age.secrets.funkwhale-typesense-api-key;
              ldap = config.age.secrets.lldap-admin-password;
            };
            script =
              {
                pkgs,
                lib,
                decrypt,
                deps,
                ...
              }:
              ''
                printf 'DJANGO_SECRET_KEY=%s\n' "$(${pkgs.pwgen}/bin/pwgen -s 64 1)"
                printf 'TYPESENSE_API_KEY=%s\n' "$(${decrypt} ${lib.escapeShellArg deps.typesense.file})"
                printf 'LDAP_BIND_PASSWORD=%s\n' "$(${decrypt} ${lib.escapeShellArg deps.ldap.file})"
              '';
          };
        };

        services.funkwhale = {
          enable = true;
          package = fwPkgs.funkwhale;
          configureNginx = true;
          secretEnvironmentFile = config.age.secrets.funkwhale-env.path;
          settings = {
            FUNKWHALE_HOSTNAME = fqdn;
            FUNKWHALE_PROTOCOL = "https";
            # The module sets these without mkDefault; move both off the
            # (small) /persist pool onto zdata.
            MUSIC_DIRECTORY_PATH = lib.mkForce musicDir;
            MEDIA_ROOT = lib.mkForce mediaDir;
            # Album uploads come in as single big archives.
            NGINX_MAX_BODY_SIZE = "1G";

            TYPESENSE_URL = "http://127.0.0.1:${toString typesensePort}";

            LDAP_ENABLED = true;
            LDAP_SERVER_URI = "ldap://127.0.0.1:3890";
            # OpenLDAP's ACL is `by users read`, so searching needs a bound
            # identity: the directory admin, like calibre-web and Jellyfin.
            LDAP_BIND_DN = "uid=admin,ou=people,${ldapBaseDn}";
            LDAP_ROOT_DN = "ou=people,${ldapBaseDn}";
            LDAP_SEARCH_FILTER = "(&(objectClass=person)(!(uid=admin))(|(uid={0})(mail={0})))";
            LDAP_USER_ATTR_MAP = "first_name:givenName, last_name:sn, username:uid, email:mail";
          };
        };

        services.typesense = {
          enable = true;
          package = fwPkgs.typesense;
          settings.server = {
            api-address = "127.0.0.1";
            api-port = typesensePort;
          };
          # The unit is DynamicUser= and `cat`s this file as that user, so hand
          # it the agenix secret through the manager instead.
          apiKeyFile = "/run/credentials/typesense.service/api-key";
        };
        systemd.services =
          lib.genAttrs funkwhaleUnits (_: {
            wants = [ "typesense.service" ];
            unitConfig.RequiresMountsFor = [ "/srv/media" ];
          })
          // {
            typesense.serviceConfig.LoadCredential = [
              "api-key:${config.age.secrets.funkwhale-typesense-api-key.path}"
            ];
          };

        users.users.funkwhale.extraGroups = [ "transmission" ];
        users.users.nginx.extraGroups = [ "transmission" ];

        # Setgid like the rest of /srv/media so everything below keeps the
        # shared group.
        systemd.tmpfiles.rules = [
          "d ${musicDir} 2770 funkwhale transmission -"
          "d ${mediaDir} 2770 funkwhale transmission -"
        ];

        services.nginx.virtualHosts.${fqdn} = {
          forceSSL = true;
          enableACME = true;
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "music" ];

        # /var/lib/funkwhale is created by tmpfiles before any unit runs, so
        # give the /persist source the right owner up front (see CLAUDE.md,
        # Persistence). Redis uses StateDirectory=, Typesense is DynamicUser=
        # (hence /var/lib/private), and Postgres is already persisted by
        # src/keycloak.nix.
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/funkwhale";
            user = "funkwhale";
            group = "funkwhale";
            mode = "0750";
          }
        ];
        state.directories = [
          "/var/lib/redis-funkwhale"
          "/var/lib/private/typesense"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
