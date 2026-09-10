{
  systems.family.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        instance = "default";
        service = "authelia-${instance}";
        stateDir = "/var/lib/${service}";
        usersFile = "${stateDir}/users.yaml";
        port = 9091;
        upstream = "http://[::1]:${toString port}";
        domain = config.networking.domain;
        fqdn = "auth.${domain}";
        accounts = lib.attrValues config.localAccounts;
        # authelia auth
        forwardedHeaders = ''
          proxy_set_header X-Original-Method $request_method;
          proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
          proxy_set_header X-Forwarded-Method $request_method;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-URI $request_uri;
          proxy_set_header X-Forwarded-For $remote_addr;
        '';
      in
      {
        options.authelia.protectedVhosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "calendar.apostolforemny.de" ];
        };

        config = lib.mkMerge [
          {
            services.authelia.instances.${instance} = {
              enable = true;
              secrets.manual = true;
              settings = {
                server.address = "tcp://[::1]:${toString port}";
                # iOS does not support login/ cookies
                server.endpoints.authz.auth-request = {
                  implementation = "AuthRequest";
                  authn_strategies = [
                    {
                      name = "HeaderAuthorization";
                      schemes = [ "Basic" ];
                      scheme_basic_cache_lifespan = 0;
                    }
                  ];
                };
                access_control.default_policy = "one_factor";
                authentication_backend.file = {
                  path = usersFile;
                  watch = true;
                };
                notifier.filesystem.filename = "${stateDir}/notifier.txt";
                session.cookies = [
                  {
                    inherit domain;
                    authelia_url = "https://${fqdn}";
                    default_redirection_url = "https://${domain}";
                  }
                ];
                storage.local.path = "${stateDir}/storage.sqlite3";
              };
            };

            systemd.services.${service} = {
              environment = {
                AUTHELIA_JWT_SECRET_FILE = "%d/jwtSecret";
                AUTHELIA_SESSION_SECRET_FILE = "%d/sessionSecret";
                AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE = "%d/storageEncryptionKey";
              };
              serviceConfig.LoadCredential =
                lib.map
                  (
                    name:
                    "${name}:${pkgs.asecret-lib.password "per-host/${config.networking.hostName}/per-service/${service}/${name}"}"
                  )
                  [
                    "jwtSecret"
                    "sessionSecret"
                    "storageEncryptionKey"
                  ];
            };
          }

          {
            systemd.services."${service}-users" = {
              description = "Render ${service}'s file authentication backend";
              before = [ "${service}.service" ];
              wantedBy = [ "${service}.service" ];
              path = with pkgs; [
                authelia
                coreutils
                jq
                json2yaml
              ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = service;
                Group = service;
                StateDirectory = service;
                StateDirectoryMode = "0700";
                LoadCredential = lib.map ({ username, passwordFile, ... }: "${username}:${passwordFile}") accounts;
              };
              script = ''
                set -efu
                umask 0177
                for username in ${lib.escapeShellArgs (lib.map ({ username, ... }: username) accounts)}; do
                  hashedPassword=$(
                    authelia crypto hash generate argon2 \
                      --password "$(cat "$CREDENTIALS_DIRECTORY/$username")" |
                    cut -d' ' -f2-
                  )
                  jq -cn --arg username "$username" --arg hashedPassword "$hashedPassword" \
                    '{ key: $username, value: { displayname: $username, password: $hashedPassword } }'
                done |
                jq -s '{ users: from_entries }' |
                json2yaml > ${lib.escapeShellArg usersFile}
              '';
            };
          }

          {
            services.nginx = {
              enable = true;
              virtualHosts.${fqdn} = {
                enableACME = true;
                forceSSL = true;
                locations = {
                  "/" = {
                    proxyPass = upstream;
                    recommendedProxySettings = true;
                    extraConfig = forwardedHeaders;
                  };
                  "/api/authz".proxyPass = upstream;
                  "/api/verify".proxyPass = upstream;
                };
              };
            };
            networking.extraHosts = "::1 ${fqdn}";
            networking.firewall.allowedTCPPorts = [
              80
              443
            ];
            state.directories = [
              stateDir
              "/var/lib/acme"
            ];
          }

          {
            services.nginx.virtualHosts = lib.genAttrs config.authelia.protectedVhosts (_: {
              locations = {
                "/".extraConfig = ''
                  auth_request /internal/authelia/authz;
                  auth_request_set $user $upstream_http_remote_user;
                  auth_request_set $groups $upstream_http_remote_groups;
                  auth_request_set $name $upstream_http_remote_name;
                  auth_request_set $email $upstream_http_remote_email;
                  auth_request_set $redirection_url $upstream_http_location;
                  proxy_set_header Remote-User $user;
                  proxy_set_header Remote-Groups $groups;
                  proxy_set_header Remote-Email $email;
                  proxy_set_header Remote-Name $name;
                  # A browser is sent to the login form; iOS' accountsd retries
                  # with credentials on a bare 401 but follows a redirect into
                  # the login page and never recovers, so leave its 401 alone.
                  if ($http_user_agent !~* 'accountsd/1.0') {
                    error_page 401 =302 $redirection_url;
                  }
                '';
                "/internal/authelia/authz" = {
                  proxyPass = "https://${fqdn}/api/authz/auth-request";
                  extraConfig = ''
                    internal;

                    ${forwardedHeaders}
                    proxy_set_header Content-Length "";
                    proxy_set_header Connection "";
                    proxy_pass_request_body off;
                    proxy_http_version 1.1;
                  '';
                };
              };
            });
          }
        ];
      }
    )
  ];
}
