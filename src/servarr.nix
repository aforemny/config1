{
  # PERMISSIONS: Transmission, Sonarr, Radarr, Lidarr, Readarr, Bazarr and
  # Jellyfin all run with
  # 'transmission' as their PRIMARY group -- PrivateUsers=true (on every one of
  # these units) maps only the unit's own user+group into its namespace, so a
  # merely-supplementary shared group would appear as 'nobody' and grant no
  # access; the shared group must be primary. 'transmission' already owns the
  # downloads and carries a fixed gid (config.ids.gids.transmission), which
  # stays stable across tower's rootfs rollback -- unlike a freshly-allocated
  # group. The /srv/media tree is root:transmission + setgid (below).
  #
  # The cross-app wiring below the NixOS surface has no declarative module and
  # is done once in each web UI (like Jellyfin's own first-run steps). After
  # deploy:
  #   * Prowlarr (https://prowlarr.nomath.org): add indexers; under
  #     Settings -> Apps add Sonarr (http://localhost:8989), Radarr
  #     (http://localhost:7878), Lidarr (http://localhost:8686) and Readarr
  #     (http://localhost:8787) with their API keys for a Full Sync.
  #   * Sonarr / Radarr / Lidarr / Readarr: add a Transmission download client
  #     at host 192.168.15.1 port 9091 (no auth; they all share Transmission's
  #     VPN namespace, so that is an intra-namespace address -- see
  #     src/transmission.nix), category "tv" / "movies" / "music" / "books";
  #     add the root folder /srv/media/library/tv / movies / music / readarr.
  #   * Bazarr (https://bazarr.nomath.org): under Settings -> Sonarr / Radarr
  #     connect to localhost:8989 / localhost:7878 with their API keys; add
  #     subtitle providers and a language profile.
  #
  # Lidarr's root folder is Funkwhale's in-place library (src/funkwhale.nix);
  # re-run its import_files (or scan the library in the UI) to pick up new
  # albums. Readarr gets a root folder of its own instead of
  # /srv/media/library/books: calibre-web is that library's only writer
  # (src/calibre.nix), so finished books are added to it via calibre-web.
  # Readarr is retired upstream (2025); its metadata lookups may fail.
  systems.tower.modules = [
    (
      { config, lib, ... }:
      let
        # Same VPN namespace as Transmission (src/transmission.nix).
        ns = "tvpn";
        nsAddr = "192.168.15.1";
        arr = {
          sonarr = 8989;
          radarr = 7878;
          prowlarr = 9696;
          lidarr = 8686;
          readarr = 8787;
          bazarr = 6767;
        };
        externalAuth = {
          method = "External";
          required = "Enabled";
        };
      in
      {
        services.sonarr = {
          enable = true;
          group = "transmission";
          settings.auth = externalAuth;
        };
        services.radarr = {
          enable = true;
          group = "transmission";
          settings.auth = externalAuth;
        };
        services.lidarr = {
          enable = true;
          group = "transmission";
          # Upstream defaults to /var/lib/lidarr/.config/Lidarr. tmpfiles then
          # creates the intermediate .config as root inside the lidarr-owned
          # persisted /var/lib/lidarr, refuses the "unsafe path transition"
          # and never creates the dataDir. Use the persisted dir itself.
          dataDir = "/var/lib/lidarr";
          settings.auth = externalAuth;
        };
        services.readarr = {
          enable = true;
          group = "transmission";
          settings.auth = externalAuth;
        };
        # Bazarr has no declarative settings; its own auth defaults to off, so
        # oauth2-proxy (src/oauth2-proxy.nix) is its only gate.
        services.bazarr = {
          enable = true;
          group = "transmission";
          listenPort = arr.bazarr;
        };

        # Bazarr writes .srt files next to the videos, i.e. into the series /
        # movie folders Sonarr and Radarr create. Their upstream UMask 0022
        # makes those 0755 (owner-only writable); 0002 keeps them writable for
        # the shared group. Folders created before this change need a one-time
        # `chmod -R g+w /srv/media/library/{tv,movies}`.
        systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";
        systemd.services.radarr.serviceConfig.UMask = lib.mkForce "0002";
        # Prowlarr only reaches indexers and the other *arr APIs -- no media
        # access -- so it keeps its upstream DynamicUser sandbox untouched.
        services.prowlarr = {
          enable = true;
          settings.auth = externalAuth;
        };

        systemd.services.sonarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];
        systemd.services.radarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];
        systemd.services.lidarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];
        systemd.services.readarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];
        systemd.services.bazarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];

        # Confine the download-automation layer to Transmission's VPN namespace:
        # indexer searches and .torrent/magnet fetches egress through the
        # tunnel (kill-switched, fail-closed) instead of tower's ISP link, and
        # the *arrs reach Transmission's RPC intra-namespace (and Bazarr reaches
        # Sonarr/Radarr on localhost). Trade-off:
        # some indexers/trackers Cloudflare-challenge or block VPN exit IPs --
        # if that bites Prowlarr, drop its vpnConfinement (Sonarr/Radarr stay
        # confined, still hiding the .torrent fetches).
        systemd.services.sonarr.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };
        systemd.services.radarr.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };
        systemd.services.prowlarr.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };
        systemd.services.lidarr.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };
        systemd.services.readarr.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };
        systemd.services.bazarr.vpnConfinement = {
          enable = true;
          vpnNamespace = ns;
        };

        # Route each UI port from the host into the netns and open it there, so
        # nginx (host) can proxy in -- mirrors transmission's RPC portMapping.
        vpnNamespaces.${ns}.portMappings = map (port: {
          from = port;
          to = port;
          protocol = "tcp";
        }) (lib.attrValues arr);

        systemd.tmpfiles.rules = [
          "d /srv/media 2770 root transmission -"
          "d /srv/media/downloads 2770 root transmission -"
          "d /srv/media/downloads/.incomplete 2770 root transmission -"
          "d /srv/media/downloads/tv 2770 root transmission -"
          "d /srv/media/downloads/movies 2770 root transmission -"
          "d /srv/media/downloads/music 2770 root transmission -"
          "d /srv/media/downloads/books 2770 root transmission -"
          "d /srv/media/library 2770 root transmission -"
          "d /srv/media/library/tv 2770 root transmission -"
          "d /srv/media/library/movies 2770 root transmission -"
          "d /srv/media/library/readarr 2770 root transmission -"
        ];

        services.nginx = {
          enable = true;
          virtualHosts = lib.mapAttrs' (
            name: port:
            lib.nameValuePair "${name}.nomath.org" {
              forceSSL = true;
              enableACME = true;
              locations."/" = {
                proxyPass = "http://${nsAddr}:${toString port}";
                proxyWebsockets = true;
                recommendedProxySettings = true;
              };
            }
          ) arr;
        };

        security.acme = {
          acceptTerms = true;
          defaults.email = "aforemny@posteo.de";
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = lib.attrNames arr;

        # Radarr, Lidarr, Readarr and Bazarr create their state dirs via
        # tmpfiles (not StateDirectory=), so under impermanence the bind-mount
        # root would default to root:root and they could not write their
        # dataDir. Persist them with explicit ownership. Sonarr uses
        # StateDirectory= and Prowlarr is DynamicUser (both get chowned by
        # systemd), so bare strings work there.
        environment.persistence."/persist".directories =
          map
            (name: {
              directory = "/var/lib/${name}";
              user = name;
              group = "transmission";
              mode = "0700";
            })
            [
              "radarr"
              "lidarr"
              "readarr"
              "bazarr"
            ];

        state.directories = [
          "/var/lib/sonarr"
          "/var/lib/private/prowlarr"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
