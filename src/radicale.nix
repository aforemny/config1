{
  # The family CalDAV/CardDAV server on family, published twice:
  #
  #   calendar.apostolforemny.de   behind authelia (src/authelia.nix)
  #   calendar1.apostolforemny.de  straight to radicale
  #
  # Both endpoints authenticate the same `localAccounts` credentials -- authelia
  # checks the HTTP Basic header, radicale then checks it again against its own
  # htpasswd file -- so the second vhost is the fallback for a client that
  # cannot get past the gateway. x1e's vdirsyncer uses the first
  # (src/systems/x1e.nix).
  systems.family.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        port = 5232;
        upstream = "http://[::1]:${toString port}";
        collections = "/var/lib/radicale/collections";
        htpasswdFile = "/etc/radicale/users";
        domain = config.networking.domain;
        accounts = lib.attrValues config.localAccounts;
        vhost = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = upstream;
            recommendedProxySettings = true;
            # recommendedProxySettings leaves nginx talking HTTP/1.0 upstream,
            # which drops keepalive for every CalDAV report a client sends.
            extraConfig = "proxy_http_version 1.1;";
          };
        };
      in
      lib.mkMerge [
        {
          services.radicale = {
            enable = true;
            settings = {
              # nginx is the only client; never listen on a public address.
              server.hosts = [ "[::1]:${toString port}" ];
              storage.filesystem_folder = collections;
              auth = {
                type = "htpasswd";
                htpasswd_encryption = "bcrypt";
                htpasswd_filename = htpasswdFile;
              };
            };
          };

          # radicale's own unit creates the collections directory through
          # StateDirectory=, so systemd chowns the /persist bind mount at start
          # and a bare string entry is enough here.
          state.directories = [
            collections
            "/var/lib/acme" # TLS certificates
          ];
        }

        {
          # Render the htpasswd file from `localAccounts` on every start: the
          # passwords arrive as credentials and are bcrypt-hashed here, so no
          # hash ends up in the world-readable nix store. Type=oneshot (not the
          # implicit simple) is what makes `before=` actually mean "the file
          # exists before radicale reads it".
          systemd.services.radicale-users = {
            description = "Render radicale's htpasswd file";
            before = [ "radicale.service" ];
            wantedBy = [ "radicale.service" ];
            path = with pkgs; [
              apacheHttpd
              coreutils
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "radicale";
              Group = "radicale";
              LoadCredential = lib.map ({ username, passwordFile, ... }: "${username}:${passwordFile}") accounts;
            };
            script = ''
              set -efu
              umask 0177
              for username in ${lib.escapeShellArgs (lib.map ({ username, ... }: username) accounts)}; do
                htpasswd -Bni "$username" < "$CREDENTIALS_DIRECTORY/$username"
              done > ${lib.escapeShellArg htpasswdFile}
            '';
          };
          # /etc is on the rolled-back rootfs, so the directory the unit above
          # writes into is recreated on every boot.
          systemd.tmpfiles.rules = [
            "d ${builtins.dirOf htpasswdFile} 1775 radicale radicale"
          ];
        }

        {
          services.nginx = {
            enable = true;
            virtualHosts = {
              "calendar.${domain}" = vhost;
              "calendar1.${domain}" = vhost;
            };
          };
          authelia.protectedVhosts = [ "calendar.${domain}" ];
          networking.firewall.allowedTCPPorts = [
            80
            443
          ];
        }
      ]
    )
  ];
}
