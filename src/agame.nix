{
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "agame.nomath.org";
        agame = import ../../agame { }; # TODO
      in
      {
        systemd.services.agame = {
          description = "agame headless multiplayer server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            ExecStart = "${agame.agame}/bin/agame --server";
            DynamicUser = true;
            Restart = "on-failure";
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              root = agame.agame-web;
              tryFiles = "$uri $uri/ /index.html";
              extraConfig = ''
                recursive_error_pages on;
                error_page 418 = @websocket;
                if ($http_upgrade) {
                  return 418;
                }
              '';
            };
            locations."@websocket" = {
              proxyPass = "http://127.0.0.1:16385";
              proxyWebsockets = true;
            };
          };
        };

        security.acme = {
          acceptTerms = true;
          defaults.email = "aforemny@posteo.de";
        };

        networking.firewall = {
          allowedTCPPorts = [
            80
            443
          ];
          allowedUDPPorts = [ 16384 ];
        };

        dns.dynamicAAAA = [ "agame" ];

        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
