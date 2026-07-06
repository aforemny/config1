{ sources, ... }:
{
  systems.tower.modules = [
    "${sources.declarative-runtime}/services/jellyfin/module.nix"
    (
      let
        fqdn = "j.nomath.org";
        port = 8096;
      in
      {
        services.jellyfin = {
          enable = true;
          # Share the media stack's primary group so Jellyfin can read the
          # library that Sonarr/Radarr populate on /srv/media (see
          # src/servarr.nix). PrivateUsers=true on jellyfin.service maps only
          # the unit's own user+group, so this must be the PRIMARY group, not a
          # supplementary one. Jellyfin's own state is 0700 (UMask 0077), so
          # the group carries no extra access to it.
          group = "transmission";

          runtime = {
            enable = true;
            libraries.movies = {
              collection_type = "movies";
              paths = [ "/srv/media/library/movies" ];
            };
            libraries.shows = {
              collection_type = "tvshows";
              paths = [ "/srv/media/library/tv" ];
            };
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              proxyWebsockets = true;
              recommendedProxySettings = true;
              extraConfig = ''
                proxy_buffering off; # don't buffer media streams
                client_max_body_size 20M; # subtitle / plugin uploads
              '';
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

        dns.dynamicAAAA = [ "j" ];

        # /var/lib/jellyfin is created by the module via tmpfiles, not
        # StateDirectory=, so under impermanence its bind-mount root defaults to
        # root:root and Jellyfin cannot create its dataDir. Persist it with
        # explicit ownership so impermanence creates the /persist source owned
        # by the service (group 'transmission' to match services.jellyfin.group).
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/jellyfin";
            user = "jellyfin";
            group = "transmission";
            mode = "0700";
          }
        ];

        state.directories = [
          # Mint-once admin password for the runtime reconciler. Its unit uses
          # StateDirectory= (systemd chowns the bind mount at start), so a bare
          # string is fine. Losing it to the rootfs rollback would strand the
          # reconciler's credential for the admin it already created.
          "/var/lib/declarative-jellyfin-password"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
