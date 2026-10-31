{
  # Stalwart at https://cal.nomath.org: calendars (and contacts) shared per
  # calendar between the realm's users, read-only or read-write, set from the
  # web UI. Radicale on family stays as it is.
  #
  # MAIL. Internal only, at mail1.nomath.org: IMAPS (993) and submission
  # (465) for the same accounts, delivering between them. There is no SMTP
  # listener on 25 and relaying to other domains is refused, so nothing is
  # received from or sent to the internet -- nomath.org's MX stays maddy on
  # family, so these addresses do not exist outside Stalwart.
  #
  # VERSION. 0.16 is pinned on purpose: it keeps all configuration in its
  # database and is managed over JMAP, so nixpkgs' services.stalwart (TOML,
  # 0.15) does not apply -- this file runs the binary with its own unit. The
  # on-disk config.json only names the datastore; everything else is the
  # declarative `plan` below, which `stalwart-cli apply` reconciles on every
  # start.
  #
  # SEEDING. On a database without listeners, a normal start creates defaults
  # on [::] (25, 443, 4190, 8080, ...), colliding with nginx and radicle-httpd.
  # So every start first runs Stalwart in recovery mode, which binds only
  # `recoveryPort`, applies the plan there, and only then starts it normally
  # with the single loopback listener the plan declares.
  #
  # AUTH. Keycloak's `nomath` realm is the account directory (OIDC). Accounts
  # are created on first web-UI login as <preferred_username>@nomath.org; the
  # web UI only sends a login to Keycloak when the full address is entered.
  # Devices use app passwords created in the web UI (/account); those are
  # checked by Stalwart itself, so CalDAV keeps working without Keycloak. The
  # fallback `admin` (password below) can always log in, also at /admin.
  #
  # Calendar e-mail (alarms, iMIP invitations) is off, as it would have to
  # leave the server.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "cal.nomath.org";
        issuer = "https://keycloak.nomath.org/realms/${realm}";
        mailFqdn = "mail1.nomath.org";
        acmeDir = config.security.acme.certs.${mailFqdn}.directory;
        domain = "nomath.org";
        realm = "nomath";
        # Keycloak client of the web UI; Stalwart injects it into the UI's
        # index.html (Application.oauthClientId below).
        clientId = "stalwart-webui";
        port = 8097;
        recoveryPort = 8098;
        package = pkgs.stalwart_0_16;
        dataDir = "/var/lib/stalwart";

        configFile = pkgs.writeText "stalwart-config.json" (
          builtins.toJSON {
            "@type" = "RocksDb";
            path = "${dataDir}/db";
          }
        );

        # One `stalwart-cli apply` operation per line. `reconcile` also removes
        # objects of that type the plan does not declare; `#name` refers to an
        # object declared earlier in the plan. Sets are encoded as
        # { <element> = true; }.
        set = xs: lib.genAttrs xs (_: true);
        plan = pkgs.writeText "stalwart-plan.ndjson" (
          lib.concatMapStringsSep "\n" builtins.toJSON [
            {
              "@type" = "reconcile";
              object = "NetworkListener";
              matchOn = [ "name" ];
              value = {
                http = {
                  name = "http";
                  bind = set [ "[::1]:${toString port}" ];
                  protocol = "http";
                  useTls = false;
                };
                imaps = {
                  name = "imaps";
                  bind = set [ "[::]:993" ];
                  protocol = "imap";
                  useTls = true;
                  tlsImplicit = true;
                };
                submissions = {
                  name = "submissions";
                  bind = set [ "[::]:465" ];
                  protocol = "smtp";
                  useTls = true;
                  tlsImplicit = true;
                };
              };
            }
            {
              # Read from the ACME files on every start (restarted on renewal).
              "@type" = "reconcile";
              object = "Certificate";
              matchOn = [ "certificate" ];
              value.mail1 = {
                certificate = {
                  "@type" = "File";
                  filePath = "${acmeDir}/fullchain.pem";
                };
                privateKey = {
                  "@type" = "File";
                  filePath = "${acmeDir}/key.pem";
                };
              };
            }
            {
              "@type" = "upsert";
              object = "Directory";
              matchOn = [ "description" ];
              value.keycloak = {
                "@type" = "Oidc";
                description = "Keycloak";
                issuerUrl = issuer;
                claimUsername = "preferred_username";
                usernameDomain = domain;
                claimName = "name";
                requireAudience = clientId;
              };
            }
            {
              "@type" = "upsert";
              object = "Domain";
              matchOn = [ "name" ];
              value.nomath = {
                name = domain;
                # No mail is sent from here; don't mint DKIM keys.
                dkimManagement."@type" = "Manual";
              };
            }
            {
              # The server-wide directory: a per-domain directoryId is an
              # enterprise feature and ignored otherwise.
              "@type" = "update";
              object = "Authentication";
              value.directoryId = "#keycloak";
            }
            {
              "@type" = "update";
              object = "SystemSettings";
              value = {
                defaultHostname = mailFqdn;
                defaultDomainId = "#nomath";
                defaultCertificateId = "#mail1";
              };
            }
            {
              # Internal only: authenticated users may not relay elsewhere.
              "@type" = "update";
              object = "MtaStageRcpt";
              value.allowRelaying."else" = "false";
            }
            {
              "@type" = "update";
              object = "Http";
              value.useXForwarded = true; # behind nginx
            }
            {
              "@type" = "update";
              object = "CalendarAlarm";
              value.enable = false;
            }
            {
              "@type" = "update";
              object = "CalendarScheduling";
              value = {
                enable = false;
                httpRsvpEnable = false;
              };
            }
            {
              # Serve the packaged web UI instead of fetching it from GitHub.
              # Stalwart caches the bundle per Application object, so the
              # version is part of the match key: an update replaces the object
              # and with it the cached bundle.
              "@type" = "reconcile";
              object = "Application";
              matchOn = [ "description" ];
              value.webui = {
                description = "Stalwart Web Interface ${package.webui.version}";
                resourceUrl = "file://${package.webui}/webui.zip";
                autoUpdateFrequency = 365 * 24 * 60 * 60 * 1000;
                oauthClientId = clientId;
                unpackDirectory = "/var/cache/stalwart/webui";
                urlPrefix = set [
                  "/admin"
                  "/account"
                ];
                enabled = true;
              };
            }
          ]
        );
      in
      {
        age.secrets.stalwart-admin-password.generator.script = "alnum";

        users.users.stalwart = {
          isSystemUser = true;
          group = "stalwart";
        };
        users.groups.stalwart = { };

        systemd.services.stalwart = {
          description = "Stalwart";
          wantedBy = [ "multi-user.target" ];
          # acme-<cert> provides a placeholder certificate until the real one
          # is issued, so the Certificate files always exist.
          after = [
            "network-online.target"
            "acme-${mailFqdn}.service"
            "keycloak.service"
            "nginx.service"
          ];
          wants = [
            "network-online.target"
            "acme-${mailFqdn}.service"
          ];
          restartTriggers = [
            configFile
            plan
          ];
          path = [
            package
            pkgs.curl
            pkgs.stalwart-cli
          ];
          environment = {
            STALWART_HOSTNAME = fqdn;
            # stalwart-cli caches the server schema under $HOME.
            HOME = "/var/cache/stalwart";
          };
          script = ''
            set -euo pipefail
            STALWART_RECOVERY_ADMIN="admin:$(< "$CREDENTIALS_DIRECTORY/admin-password")"
            export STALWART_RECOVERY_ADMIN

            STALWART_RECOVERY_MODE=1 STALWART_RECOVERY_MODE_PORT=${toString recoveryPort} \
              stalwart --config=${configFile} &
            recovery=$!
            until curl -so /dev/null "http://[::1]:${toString recoveryPort}/"; do
              kill -0 "$recovery"
              sleep 1
            done
            STALWART_URL="http://[::1]:${toString recoveryPort}" \
              STALWART_USER=admin \
              STALWART_PASSWORD="''${STALWART_RECOVERY_ADMIN#admin:}" \
              stalwart-cli apply --quiet --no-color --file ${plan}
            kill -INT "$recovery"
            wait "$recovery" || true

            # The Keycloak directory is given up on 30 seconds after Stalwart
            # starts (until the next restart), and Keycloak boots slower. Wait
            # for it, but not indefinitely: CalDAV and mail work without it.
            for _ in $(seq 120); do
              curl -sfo /dev/null "${issuer}/.well-known/openid-configuration" && break
              sleep 1
            done

            exec stalwart --config=${configFile}
          '';
          serviceConfig = {
            Type = "simple";
            User = "stalwart";
            Group = "stalwart";
            LoadCredential = [ "admin-password:${config.age.secrets.stalwart-admin-password.path}" ];
            StateDirectory = "stalwart";
            StateDirectoryMode = "0700";
            CacheDirectory = [
              "stalwart"
              "stalwart/webui" # Stalwart does not create unpackDirectory itself.
            ];
            KillMode = "process";
            KillSignal = "SIGINT";
            Restart = "on-failure";
            RestartSec = 5;
            LimitNOFILE = 65536;

            # Binds 465 and 993.
            AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
            CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
            DeviceAllow = "";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            PrivateUsers = false; # incompatible with CAP_NET_BIND_SERVICE
            ProcSubset = "pid";
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "@system-service"
              "~@privileged"
            ];
            UMask = "0077";
          };
        };

        # A public PKCE client for the web UI. The audience mapper lets
        # Stalwart insist (requireAudience) on tokens issued for it, not for
        # any other client of the realm.
        services.keycloak.runtime = {
          openid_clients.${clientId} = {
            inherit realm;
            enabled = true;
            access_type = "PUBLIC";
            standard_flow_enabled = true;
            pkce_code_challenge_method = "S256";
            valid_redirect_uris = [
              "https://${fqdn}/admin/oauth/callback"
              "https://${fqdn}/account/oauth/callback"
            ];
            web_origins = [ "https://${fqdn}" ];
          };
          openid_audience_protocol_mappers.${clientId} = {
            inherit realm;
            client = clientId;
            included_client_audience = clientId;
            add_to_access_token = true;
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://[::1]:${toString port}";
              proxyWebsockets = true;
              recommendedProxySettings = true;
              extraConfig = "client_max_body_size 64m;";
            };
          };
          # Only answers the ACME challenge; the certificate is Stalwart's.
          virtualHosts.${mailFqdn}.locations."/.well-known/acme-challenge".root =
            "/var/lib/acme/acme-challenge";
        };
        security.acme.certs.${mailFqdn} = {
          webroot = "/var/lib/acme/acme-challenge";
          group = "stalwart";
          reloadServices = [ "stalwart.service" ];
        };
        systemd.services."acme-order-renew-${mailFqdn}" = {
          after = [ "nginx.service" ];
          wants = [ "nginx.service" ];
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
          465 # submission (implicit TLS)
          993 # IMAPS
        ];

        # Published as cal.nomath.org and mail1.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [
          "cal"
          "mail1"
        ];

        # Stalwart runs as a static user and creates its directory through
        # StateDirectory=, so systemd chowns the bind mount at start and a bare
        # string entry is enough.
        state.directories = [
          dataDir
          "/var/lib/acme" # TLS certificates
        ];
      }
    )
  ];
}
