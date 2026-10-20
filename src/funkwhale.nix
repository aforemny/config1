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
  # LIBRARY.
  #   /srv/media/library/music       MUSIC_DIRECTORY_PATH, the in-place
  #                                  library on zdata next to the rest of the
  #                                  media stack, and Lidarr's root folder
  #                                  (src/servarr.nix). funkwhale-import-music
  #                                  (below) imports it into aforemny's
  #                                  "instance" library and then watches it
  #                                  for new/changed/deleted files.
  #   /var/lib/funkwhale/data/media  MEDIA_ROOT (module default): uploads,
  #                                  covers, avatars. Funkwhale-specific, so
  #                                  it stays in the persisted state dir.
  # Both are served by nginx directly (X-Accel via /_protected/). For the
  # music dir, nginx and funkwhale join the shared `transmission` group
  # (src/servarr.nix); neither unit runs PrivateUsers=, so a supplementary
  # group is enough here. MEDIA_ROOT is world-readable (module tmpfiles, 0755).
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
        # celery 5.6.3 on Python 3.14 builds its call-argument check from
        # inspect.signature(), which follows __wrapped__ (unlike the
        # getfullargspec it used before 3.14). Funkwhale's require_instance
        # decorator (taskapp/celery.py) is functools.wraps over an (*args,
        # **kwargs) wrapper that turns `<name>_id=` into the model instance, so
        # celery now validates `.delay(upload_id=...)` against the *inner*
        # signature and raises
        #   TypeError: process_upload() got an unexpected keyword argument 'upload_id'
        # in the web process -- every upload 500s, as does every other of the
        # ~27 require_instance tasks. Backport celery main's fix
        # (follow_wrapped=False). Scoped to funkwhale's own python set; drop it
        # once the pin carries a celery with the fix.
        fwPython = fwPkgs.python3.override {
          self = fwPython;
          packageOverrides = _: super: {
            # Funkwhale subclasses django-oauth-toolkit's abstract models
            # (users.Application/Grant/AccessToken/RefreshToken, swapped in via
            # OAUTH2_PROVIDER_*_MODEL), so its own migrations must match the
            # toolkit's fields. Upstream pins 3.1.0; nixpkgs' 3.4.1 adds
            # `resource` (RFC 8707), `token_checksum`, `cimd_expires_at` and
            # `registration_source`, which no funkwhale migration creates, so
            # every OAuth-authenticated request -- e.g. the web player's
            # /api/v2/listen/?token=..., i.e. all browser playback -- 500s with
            #   psycopg2.errors.UndefinedColumn: column users_accesstoken.resource does not exist
            # Go back to upstream's pin rather than adding columns funkwhale
            # does not know about. No DB change either way: the toolkit's own
            # migrations never ran (its models are swapped out). Drop once
            # funkwhale pins a release with these fields.
            django-oauth-toolkit = super.django-oauth-toolkit.overridePythonAttrs (old: {
              version = "3.1.0";
              src = old.src.override {
                tag = "3.1.0";
                hash = "sha256-c7LaB8426qjwDveec3BghqCEtPs572PTVodvLAO2CcQ=";
              };
            });
            celery = super.celery.overridePythonAttrs (old: {
              postPatch = (old.postPatch or "") + ''
                substituteInPlace celery/utils/functional.py \
                  --replace-fail \
                    'sig = inspect.signature(target, annotation_format=_annotationlib.Format.STRING)' \
                    'sig = inspect.signature(target, follow_wrapped=False, annotation_format=_annotationlib.Format.STRING)'
              '';
            });
          };
        };
        musicDir = "/srv/media/library/music";
        typesensePort = 8108;
        # aforemny's built-in "instance" library (visible to every account on
        # this instance). Its row lives in the persisted Postgres, so the UUID
        # is stable; look libraries up with
        #   funkwhale-manage shell -c "from funkwhale_api.music.models import \
        #     Library; print(list(Library.objects.values_list('uuid', \
        #     'actor__preferred_username', 'privacy_level')))"
        musicLibrary = "fe0891cf-8558-41e8-8c3b-eba1352f710c";
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
          # Upstream 2.0.11 gives an account its built-in libraries (one per
          # privacy level: me/instance/everyone) only on signup
          # (users/serializers.py) and `fw users create` (cli/users.py). The
          # LDAP hook, init_ldap_user, creates just the federation actor, so
          # every LDAP-created account has no library at all and the web UI's
          # uploads all fail with HTTP 400. Create them there too, whenever the
          # actor has none. ldap_populate_user fires on every LDAP login, so
          # this also repairs accounts created before the fix on their next
          # login. --replace-fail breaks the build once upstream changes the
          # hook, instead of going quietly stale.
          package = (fwPkgs.funkwhale.override { python3 = fwPython; }).overridePythonAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace funkwhale_api/users/models.py \
                --replace-fail \
                  '        user.actor = create_actor(user)' \
                  '        user.actor = create_actor(user)
                  if not music_models.Library.objects.filter(actor=user.actor).exists():
                      create_user_libraries(user)'
            '';
          });
          configureNginx = true;
          secretEnvironmentFile = config.age.secrets.funkwhale-env.path;
          settings = {
            FUNKWHALE_HOSTNAME = fqdn;
            FUNKWHALE_PROTOCOL = "https";
            # The module sets this without mkDefault; move the music library
            # off the (small) /persist pool onto zdata.
            MUSIC_DIRECTORY_PATH = lib.mkForce musicDir;
            # Album uploads come in as single big archives.
            NGINX_MAX_BODY_SIZE = "1G";

            # redis-py 8 (nixpkgs; upstream pins 7.4.1) changed the default
            # socket_timeout from None to 5s. channels_redis waits for messages
            # with BZPOPMIN timeout=5, so on an idle WebSocket the client read
            # gives up exactly when the server would answer: the /api/v2/activity
            # consumer dies with "TimeoutError: Timeout reading from
            # .../redis.sock" and the browser reconnects every ~6s, dropping
            # live notifications. CACHE_URL is handed verbatim to both
            # django-redis and channels_redis (CHANNEL_LAYERS reuses the cache
            # LOCATION), and both parse socket_timeout from the URL query. The
            # module sets this without mkDefault, hence mkForce.
            CACHE_URL = lib.mkForce "unix://${config.services.redis.servers.funkwhale.unixSocket}?db=0&socket_timeout=30";

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
            # Keeps the in-place library in sync with musicDir, which Lidarr
            # fills. import_files --watch only sees changes made while it
            # runs, so first do a plain import to catch up (files already in
            # the library are skipped), then hand over to watch mode. --prune
            # drops artists/albums left without tracks after deletions.
            funkwhale-import-music = {
              description = "Funkwhale in-place import of ${musicDir}";
              after = [
                "funkwhale-setup.service"
                "typesense.service"
              ];
              requires = [ "funkwhale-setup.service" ];
              partOf = [ "funkwhale.target" ];
              wantedBy = [ "funkwhale.target" ];
              unitConfig.RequiresMountsFor = [ "/srv/media" ];
              environment = config.services.funkwhale.settings;
              script =
                let
                  importFiles = lib.escapeShellArgs [
                    (lib.getExe config.services.funkwhale.package)
                    "import_files"
                    musicLibrary
                    musicDir
                    "--recursive"
                    "--in-place"
                    "--noinput"
                    "--prune"
                  ];
                in
                # The catch-up run errors out on an empty musicDir ("No file
                # matching pattern"); that must not keep watch mode from
                # starting.
                ''
                  ${importFiles} || echo "catch-up import failed, watching anyway" >&2
                  exec ${importFiles} --watch
                '';
              serviceConfig = {
                User = "funkwhale";
                Group = "funkwhale";
                # troi looks for patches in the working directory.
                WorkingDirectory = "/var/lib/funkwhale";
                EnvironmentFile = [
                  config.services.funkwhale.secretEnvironmentFile
                  "-/var/lib/funkwhale/config/django_secret_key.env"
                ];
                Restart = "on-failure";
                RestartSec = 30;
              };
            };

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
            # nginx serves MEDIA_ROOT (data/media) from below here.
            mode = "0755";
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
