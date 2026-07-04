{
  # Media libraries and the admin account are set up through Jellyfin's
  # first-run web wizard -- the NixOS module has no declarative surface for them.
  systems.tower.modules = [
    (
      let
        fqdn = "jellyfin.nomath.org";
        port = 8096;
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

        dns.dynamicAAAA = [ "jellyfin" ];

        state.directories = [
          "/var/lib/jellyfin"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
