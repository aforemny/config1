{
  # The e-book half of tower's media stack, published twice over one library:
  #
  #   https://books.nomath.org    calibre-web -- library UI, uploads, OPDS, and
  #                               the Kobo sync endpoint the Libra Colour talks to
  #   https://calibre.nomath.org  calibre-server -- calibre's own content server:
  #                               OPDS for KOReader, the in-browser reader, and a
  #                               remote library for `calibredb --with-library <url>`
  #
  # Both serve /srv/media/library/books, which lives on zdata/local/media (see
  # platforms/tower.nix) next to the Jellyfin tree, so it is outside the rootfs
  # rollback and needs no /persist entry.
  #
  # ONE WRITER: calibre-web owns the library (uploads, metadata edits); the
  # calibre-server account is created read-only. Both processes hold their own
  # cached view of metadata.db, so two concurrent writers is how a calibre
  # library gets a corrupted/stale database. Flip the server to read-write with
  #   calibre-server --userdb /var/lib/calibre-server/users.sqlite \
  #     --manage-users -- readonly aforemny reset
  # (and expect the reconciliation problem that comes with it).
  #
  # AUTH. calibre-web authenticates three different kinds of client, so it is
  # wired three ways (see src/ldap.nix, src/oauth2-proxy.nix):
  #   * browser -> Keycloak SSO. books.nomath.org is in oauth2-proxy's
  #     protected set, and calibre-web consumes the proxied identity via its
  #     reverse-proxy header login (header X-Calibre-Web-User, filled from the
  #     Keycloak preferred_username). No second login prompt.
  #   * Kobo -> the per-user sync token in the URL (/kobo/<token>/...).
  #   * OPDS / KOReader -> HTTP Basic, verified by binding against OpenLDAP
  #     (config_login_type = LDAP), i.e. the same password as everywhere else.
  # Both device paths bypass the SSO gate in nginx, because neither can follow
  # an OIDC redirect. calibre-server cannot do any of this -- it only knows its
  # own user database (no LDAP, no OIDC, no header auth), so it keeps HTTP
  # Basic against the account seeded below and is NOT behind oauth2-proxy
  # (which would only add a second, redundant login to the same browser UI).
  #
  # Accounts are not auto-provisioned: calibre-web only *verifies* passwords
  # against LDAP and only *trusts* the proxy header, so the `aforemny` row is
  # seeded below. `admin` stays a local account -- the browser login falls back
  # to the local hash when LDAP is unreachable (web.py), which makes it the
  # break-glass account; note that OPDS Basic has no such fallback.
  #
  # KOBO SETUP (one-time, no declarative surface -- the token is minted per
  # calibre-web user and must be typed into the device):
  #   1. https://books.nomath.org -> Keycloak login (or `admin` + the local
  #      password below, via /login).
  #   2. Admin -> Users -> <user> -> "Kobo sync token" -> Create/View. It shows
  #      an api_endpoint URL of the form
  #        https://books.nomath.org/kobo/<token>
  #   3. USB-mount the Kobo, append to .kobo/Kobo/'Kobo eReader.conf' under the
  #      [OneStoreServices] section:
  #        api_endpoint=https://books.nomath.org/kobo/<token>
  #      Eject; the device's own Sync button now pulls from calibre-web.
  # The admin password is NOT admin123: calibre-web's ExecStartPre replaces the
  # shipped default with the agenix secret (read it with
  # `ssh tower cat /run/agenix/calibre-web-admin-password`); a password you set
  # yourself in the UI is left alone. Same for the calibre-server account
  # `aforemny`: /run/agenix/calibre-server-password.

  # Four defects in nixpkgs 26.11pre1075288's calibre-web, each fatal to a
  # piece of what this host is for.
  #
  # 1. It cannot start at all: upstream 0.6.27 declares its console script as
  #    `calibreweb.__main__:main`, but the tag ships no __main__ module -- the
  #    launcher is cps.py, which nixpkgs installs as calibreweb/__init__.py and
  #    which exports main itself. bin/calibre-web dies with
  #      ModuleNotFoundError: No module named 'calibreweb.__main__'
  #    before parsing a single argument, so the service and the module's own
  #    migration ExecStartPre fail alike. nixpkgs master already rewrites the
  #    entry point to `calibreweb:main`; do the same.
  # 2. jsonschema -- upstream's `kobo` extra -- is only a check input, so it is
  #    absent at runtime. cps/services/__init__.py swallows the resulting
  #    ImportError and binds SyncToken = None, which does not stop the Kobo
  #    blueprint from registering: the device authenticates fine and then every
  #    sync dies in kobo.py's SyncToken.SyncToken.from_headers(). Pull the
  #    extra into the runtime closure.
  # 3. services.calibre-web.options.enableKepubify is a no-op on Linux: it
  #    points config_kepubifypath at ${pkgs.kepubify}/bin/kepubify, but
  #    cps/binary_helper.py only accepts a binary whose *realpath* basename is
  #    `kepubify-linux-64bit`/`-32bit` (the names of upstream's release
  #    downloads), so resolve_binary_path() returns "" and no EPUB is ever
  #    kepubified -- the Kobo silently gets plain EPUBs. Accept the plain name,
  #    which is what upstream already does on FreeBSD.
  # 4. Same story as (2) for the `ldap` extra: without flask-simpleldap and
  #    python-ldap, cps/services/__init__.py binds ldap = None, calibre-web
  #    logs "Cannot activate LDAP authentication" and every OPDS Basic login
  #    fails -- config_login_type = LDAP would be dead config.
  #
  # --replace-fail means each hunk breaks the build loudly once the pin carries
  # the upstream fix, instead of going quietly stale. Note nixpkgs' own
  # postPatch has already moved cps/ to src/calibreweb/cps/ by this point.
  overlays.calibre-web = _: super: {
    calibre-web = super.calibre-web.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace pyproject.toml \
          --replace-fail 'calibre-web = "calibreweb.__main__:main"' \
                         'calibre-web = "calibreweb:main"'

        substituteInPlace src/calibreweb/cps/binary_helper.py \
          --replace-fail 'SUPPORTED_KEPUBIFY_BINARIES = ("kepubify-linux-64bit", "kepubify-linux-32bit")' \
                         'SUPPORTED_KEPUBIFY_BINARIES = ("kepubify", "kepubify-linux-64bit", "kepubify-linux-32bit")'
      '';
      propagatedBuildInputs =
        old.propagatedBuildInputs
        ++ (with super.python3Packages; [
          jsonschema # kobo extra
          flask-simpleldap # ldap extra
          python-ldap
        ]);
    });
  };

  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        library = "/srv/media/library/books";
        webFqdn = "books.nomath.org";
        serverFqdn = "calibre.nomath.org";
        webPort = 8083;
        # 8080 is radicle-httpd's loopback listener (src/radicle.nix), 8081
        # Keycloak's, 8082 argunix's.
        serverPort = 8085;
        # calibre-web's own sqlite config db, under its StateDirectory.
        appDb = "/var/lib/calibre-web/app.db";
        serverDir = "/var/lib/calibre-server";
        userDb = "${serverDir}/users.sqlite";
        account = "aforemny";
        domain = "nomath.org";
        # The directory every other service on tower authenticates against
        # (src/ldap.nix): loopback-only OpenLDAP, users under ou=people. Its
        # ACL is `by users read`, so a search needs a bound identity -- reuse
        # the directory admin, exactly like the Jellyfin plugin does.
        ldapHost = "127.0.0.1";
        ldapPort = 3890;
        ldapBaseDn = "dc=nomath,dc=org";
        ldapBindDn = "uid=admin,ou=people,${ldapBaseDn}";
        # Header carrying the SSO identity from oauth2-proxy into calibre-web.
        # Deliberately not oauth2-proxy's own X-User: that one is set by the
        # oauth2-proxy nginx snippet on `location /` only, while this one must
        # be *cleared* on the device locations below, and keeping the names
        # apart makes both halves obvious in the generated nginx config.
        proxyUserHeader = "X-Calibre-Web-User";
        webUpstream = "http://[::1]:${toString webPort}";
        webProxyCommon = ''
          client_max_body_size 1G; # book uploads
          # A first Kobo sync walks the whole library before it answers.
          proxy_read_timeout 300s;
          # calibre-web's ReverseProxied (cps/reverseproxy.py) reads the scheme
          # from X-Scheme and ignores X-Forwarded-Proto, which is all
          # recommendedProxySettings sends. Without this the Kobo sync response
          # hands the device http:// download URLs for an https-only vhost.
          proxy_set_header X-Scheme $scheme;
        '';
        # Everything the Kobo and OPDS readers talk to: no SSO gate, and the
        # proxy-identity header forcibly cleared (see the vhost below).
        deviceLocation = {
          proxyPass = webUpstream;
          recommendedProxySettings = true;
          extraConfig = webProxyCommon + ''
            auth_request off;
            proxy_set_header ${proxyUserHeader} "";
          '';
        };
        # calibre insists on a writable config directory (global prefs, the
        # server's own caches). The packaged calibre-server user would get
        # /var/lib/calibre-server as $HOME, but we run as calibre-web (see
        # below), so point calibre at the StateDirectory explicitly.
        calibreEnv = {
          HOME = serverDir;
          CALIBRE_CONFIG_DIRECTORY = "${serverDir}/config";
        };
        # Everything calibre-web keeps in app.db that has no NixOS option:
        # Kobo sync, LDAP login, reverse-proxy header login, the admin password
        # and the SSO/LDAP account row. werkzeug and cryptography are
        # calibre-web's own hashing/encryption libraries, so the values match
        # what it reads back (check_password_hash resp. the Fernet key it keeps
        # next to app.db).
        pythonEnv = pkgs.python3.withPackages (ps: [
          ps.werkzeug
          ps.cryptography
        ]);
        configureScript = pkgs.writeText "calibre-web-configure.py" ''
          import os
          import sqlite3
          import sys

          from cryptography.fernet import Fernet
          from werkzeug.security import check_password_hash, generate_password_hash

          db = sys.argv[1]
          credentials = os.environ["CREDENTIALS_DIRECTORY"]


          def credential(name):
              with open(os.path.join(credentials, name)) as f:
                  return f.read()


          # cps/__init__.py seeds this key next to app.db and decrypts every
          # `*_e` settings column with it (config_sql.ConfigSQL.load).
          with open(os.path.join(os.path.dirname(db), ".key"), "rb") as f:
              fernet = Fernet(f.read())

          settings = {
              # The endpoint the Kobo syncs against, plus pass-through of
              # everything we do not implement to Kobo's own servers, so the
              # store and firmware updates keep working.
              "config_kobo_sync": 1,
              "config_kobo_proxy": 1,
              # constants.LOGIN_LDAP. 2 is the admin UI's "Simple" bind: the
              # constant LDAP_AUTH_SIMPLE is 0 upstream (a bug -- it collides
              # with LDAP_AUTH_ANONYMOUS), and the code only ever compares
              # against the raw form values 0/1/2.
              "config_login_type": 1,
              "config_ldap_authentication": 2,
              "config_ldap_provider_url": "${ldapHost}",
              "config_ldap_port": ${toString ldapPort},
              "config_ldap_encryption": 0,
              "config_ldap_serv_username": "${ldapBindDn}",
              "config_ldap_serv_password_e": fernet.encrypt(
                  credential("ldap-password").encode()
              ).decode(),
              "config_ldap_dn": "${ldapBaseDn}",
              "config_ldap_user_object": "uid=%s",
              "config_ldap_openldap": 1,
              # SSO: trust ${proxyUserHeader} from nginx. The trusted-IP list is
              # calibre-web's own guard (reverse_proxy_auth.is_trusted_proxy_source)
              # and matches nginx on loopback; nginx overwrites the header on
              # the SSO location and clears it everywhere else.
              "config_allow_reverse_proxy_header_login": 1,
              "config_reverse_proxy_login_header_name": "${proxyUserHeader}",
              "config_reverse_proxy_trusted_ips": "127.0.0.1,::1",
          }

          con = sqlite3.connect(db)
          con.row_factory = sqlite3.Row
          con.execute(
              "update settings set " + ", ".join(name + " = ?" for name in settings),
              list(settings.values()),
          )

          # Replace the shipped default (constants.DEFAULT_PASSWORD) once. A
          # password set in the UI is left alone.
          admin = con.execute("select * from user where name = 'admin'").fetchone()
          if admin is not None and check_password_hash(admin["password"], "admin123"):
              con.execute(
                  "update user set password = ? where id = ?",
                  (generate_password_hash(credential("admin-password")), admin["id"]),
              )
              print("calibre-web: replaced the default admin password")

          # calibre-web never creates users: LDAP only verifies the password and
          # the proxy header is only matched against existing names
          # (usermanagement.load_user_from_reverse_proxy_header). Clone the admin
          # row so every column keeps a shape this schema version expects.
          if con.execute(
              "select 1 from user where name = ?", ("${account}",)
          ).fetchone() is None and admin is not None:
              user = dict(admin)
              del user["id"]
              user["name"] = "${account}"
              user["email"] = "${account}@${domain}"
              # Everything except ROLE_ANONYMOUS: admin, download, upload, edit,
              # edit shelves, delete books, viewer. No ROLE_PASSWD -- the
              # password lives in the directory, not here.
              user["role"] = 1 | 2 | 4 | 8 | 64 | 128 | 256
              # Unusable local hash: logins go through LDAP or the proxy header.
              user["password"] = generate_password_hash(os.urandom(32).hex())
              con.execute(
                  "insert into user ({}) values ({})".format(
                      ", ".join(user), ", ".join("?" * len(user))
                  ),
                  list(user.values()),
              )
              print("calibre-web: created account ${account}")

          con.commit()
          con.close()
        '';
      in
      {
        # Both passwords are sent verbatim over HTTP Basic / typed into a login
        # form, so they must not carry a trailing newline -- alnum-nonl, not
        # alnum (see src/agenix-rekey.nix).
        age.secrets.calibre-web-admin-password.generator.script = "alnum-nonl";
        age.secrets.calibre-server-password.generator.script = "alnum-nonl";

        services.calibre-web = {
          enable = true;
          # Same PRIMARY group as the rest of the media stack: /srv/media and
          # /srv/media/library are 2770 root:transmission, so with any other
          # primary group calibre-web could not even traverse into its library
          # (src/servarr.nix explains why primary and not supplementary).
          group = "transmission";
          listen = {
            ip = "::1";
            port = webPort;
          };
          options = {
            calibreLibrary = library;
            enableBookUploading = true;
            # ebook-convert out of pkgs.calibre -- the very package
            # calibre-server runs, so this costs nothing in closure size.
            enableBookConversion = true;
            # Serve EPUBs to the Kobo as its native .kepub.epub. That is what
            # gives the Libra Colour per-chapter progress, reading statistics
            # and working footnotes instead of plain-EPUB rendering.
            enableKepubify = true;
          };
        };

        # None of Kobo sync, LDAP login, the proxy-header login or the admin
        # password has a NixOS option, so do what the module itself does -- poke
        # app.db -- appended after the module's own ExecStartPre (mkAfter),
        # which has by then run the migrations that create app.db, the `admin`
        # row and the Fernet key.
        systemd.services.calibre-web.serviceConfig = {
          LoadCredential = [
            "admin-password:${config.age.secrets.calibre-web-admin-password.path}"
            # The directory bind password, shared with Keycloak/Jellyfin/maddy
            # (src/ldap.nix). Owned by the openldap user there; LoadCredential
            # is read by the manager as root, so ownership does not matter.
            "ldap-password:${config.age.secrets.lldap-admin-password.path}"
          ];
          ExecStartPre = lib.mkAfter [
            (pkgs.writeShellScript "calibre-web-configure" ''
              set -euo pipefail
              ${pythonEnv}/bin/python3 ${configureScript} ${appDb}
            '')
          ];
        };
        systemd.services.calibre-web.unitConfig.RequiresMountsFor = [ "/srv/media" ];

        services.calibre-server = {
          enable = true;
          libraries = [ library ];
          # Run as calibre-web's user so exactly one uid owns every file in the
          # library; the packaged calibre-server user would create books and
          # caches a second uid could not rewrite.
          user = "calibre-web";
          group = "transmission";
          host = "::1";
          port = serverPort;
          auth = {
            enable = true;
            # Not "auto": auto picks digest unless the connection is itself TLS,
            # and nginx terminates TLS here, so the server only ever sees plain
            # HTTP over loopback. Digest locks out most OPDS readers.
            mode = "basic";
            userDb = userDb;
          };
          # The listener is loopback-only, so advertising it over mDNS just
          # publishes an unreachable ::1 URL to the LAN.
          extraFlags = [ "--disable-use-bonjour" ];
        };

        systemd.services.calibre-server = {
          environment = calibreEnv;
          unitConfig.RequiresMountsFor = [ "/srv/media" ];
          serviceConfig = {
            # Upstream sets only User=, and only creates its own user/group when
            # the defaults are kept -- neither applies here.
            Group = "transmission";
            StateDirectory = "calibre-server";
          };
        };

        # calibre-web's ExecStartPre hard-fails on a library without
        # metadata.db, and calibre-server exits with "There is no calibre
        # library at", so mint an empty one once. LibraryDatabase() creates the
        # db as a side effect of being opened, and `list` is the cheapest
        # command that opens it. The account seeding is idempotent too, so this
        # unit simply reconciles both on every boot.
        systemd.services.calibre-bootstrap = {
          description = "Initialize the calibre library and server accounts";
          requiredBy = [
            "calibre-web.service"
            "calibre-server.service"
          ];
          before = [
            "calibre-web.service"
            "calibre-server.service"
          ];
          environment = calibreEnv;
          unitConfig.RequiresMountsFor = [ "/srv/media" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "calibre-web";
            Group = "transmission";
            StateDirectory = "calibre-server";
            LoadCredential = [ "password:${config.age.secrets.calibre-server-password.path}" ];
          };
          script = ''
            set -euo pipefail

            test -e ${library}/metadata.db ||
              ${pkgs.calibre}/bin/calibredb --with-library ${library} list >/dev/null

            manage() {
              ${pkgs.calibre}/bin/calibre-server --userdb ${userDb} --manage-users -- "$@"
            }

            # The password goes in over stdin, never argv: /proc/<pid>/cmdline
            # is world-readable.
            if manage list | ${pkgs.gnugrep}/bin/grep -qxF ${account}; then
              manage chpass ${account} < "$CREDENTIALS_DIRECTORY/password"
            else
              manage add --readonly ${account} < "$CREDENTIALS_DIRECTORY/password"
            fi
            manage readonly ${account} set
          '';
        };

        # Setgid like the rest of /srv/media so anything created below keeps the
        # shared group.
        systemd.tmpfiles.rules = [
          "d ${library} 2770 calibre-web transmission -"
        ];

        services.nginx = {
          enable = true;
          # Browser surface: behind Keycloak. src/oauth2-proxy.nix lists this
          # vhost, so that module adds `auth_request /oauth2/auth` at server
          # level plus its own snippet to `location /`.
          virtualHosts.${webFqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = webUpstream;
              recommendedProxySettings = true;
              extraConfig = webProxyCommon + ''
                # calibre-web matches the header against its own user names, so
                # hand it Keycloak's preferred_username; oauth2-proxy's
                # X-Auth-Request-User is the OIDC subject and matches nothing.
                # An empty value makes nginx drop the header, and calibre-web
                # then falls back to its normal login page.
                auth_request_set $cw_user $upstream_http_x_auth_request_preferred_username;
                proxy_set_header ${proxyUserHeader} $cw_user;
              '';
            };
            # The device surfaces authenticate themselves -- sync token in the
            # URL (/kobo/<token>/...), HTTP Basic against LDAP (/opds) -- and
            # cannot follow an OIDC redirect, so they opt out of the gate.
            # Clearing the identity header is load-bearing: calibre-web trusts
            # it from any loopback peer, i.e. from nginx, so a client-supplied
            # ${proxyUserHeader} would otherwise be a free pass into any
            # account. calibre-web's own 401 still reaches the client:
            # proxy_intercept_errors is off, so the vhost's error_page catches
            # only auth_request's own 401. /kobo_auth/ (minting tokens) is
            # admin UI and stays behind SSO.
            locations."/kobo/" = deviceLocation;
            locations."/opds" = deviceLocation;
          };
          virtualHosts.${serverFqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://[::1]:${toString serverPort}";
              recommendedProxySettings = true;
              extraConfig = ''
                # recommendedProxySettings leaves nginx talking HTTP/1.0
                # upstream, which drops keepalive for the reader's XHR storm.
                proxy_http_version 1.1;
                client_max_body_size 1G;
              '';
            };
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [
          "books"
          "calibre"
        ];

        # The library itself is on zdata and survives on its own; these are the
        # rootfs-resident bits. Both services use StateDirectory=, so systemd
        # chowns the bind mount at start and a bare string is enough.
        state.directories = [
          "/var/lib/calibre-web" # app.db: users, Kobo sync tokens, settings
          "/var/lib/calibre-server" # users.sqlite + calibre config dir
          "/var/lib/acme" # TLS certificates
        ];
      }
    )
  ];
}
