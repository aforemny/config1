{
  # PERMISSIONS: Transmission, Sonarr, Radarr and Jellyfin all run with
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
  #     Settings -> Apps add Sonarr (http://localhost:8989) and Radarr
  #     (http://localhost:7878) with their API keys for a Full Sync.
  #   * Sonarr / Radarr: add a Transmission download client at host
  #     192.168.15.1 port 9091 (no auth; Sonarr/Radarr share Transmission's
  #     VPN namespace, so that is an intra-namespace address -- see
  #     src/transmission.nix), category "tv" resp. "movies"; add the root
  #     folder /srv/media/library/tv resp. /movies.
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
        # Prowlarr only reaches indexers and the other *arr APIs -- no media
        # access -- so it keeps its upstream DynamicUser sandbox untouched.
        services.prowlarr = {
          enable = true;
          settings.auth = externalAuth;
        };

        systemd.services.sonarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];
        systemd.services.radarr.unitConfig.RequiresMountsFor = [ "/srv/media" ];

        # Confine the download-automation layer to Transmission's VPN namespace:
        # indexer searches and .torrent/magnet fetches egress through the
        # tunnel (kill-switched, fail-closed) instead of tower's ISP link, and
        # Sonarr/Radarr reach Transmission's RPC intra-namespace. Trade-off:
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
          "d /srv/media/library 2770 root transmission -"
          "d /srv/media/library/tv 2770 root transmission -"
          "d /srv/media/library/movies 2770 root transmission -"
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

        # /var/lib/radarr is created by the module via tmpfiles (not
        # StateDirectory=), so under impermanence its bind-mount root defaults
        # to root:root and Radarr cannot create its dataDir. Persist it with
        # explicit ownership. Sonarr uses StateDirectory= and Prowlarr is
        # DynamicUser (both get chowned by systemd), so bare strings work there.
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/radarr";
            user = "radarr";
            group = "transmission";
            mode = "0700";
          }
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
