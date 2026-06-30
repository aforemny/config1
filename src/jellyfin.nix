{
  # Jellyfin on tower, reachable at https://jellyfin.nomath.org. nginx
  # terminates TLS and reverse-proxies to Jellyfin's loopback HTTP listener;
  # the service's own port stays closed to the internet (openFirewall = false).
  # Media libraries and the admin account are set up through Jellyfin's
  # first-run web wizard -- the NixOS module has no declarative surface for them.
  systems.tower.modules = [
    (
      let
        fqdn = "jellyfin.nomath.org";
        port = 8096; # Jellyfin's default HTTP port; nginx is the only client.
      in
      {
        services.jellyfin.enable = true;

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              proxyWebsockets = true; # live dashboard / playback sync
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

        # Published as jellyfin.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "jellyfin" ];

        # tower rolls / back on boot; persist the library DB, metadata and
        # config. The transcode cache (/var/cache/jellyfin) is regenerable and
        # intentionally left ephemeral.
        state.directories = [
          "/var/lib/jellyfin"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
