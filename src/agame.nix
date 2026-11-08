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
        # agame's own expressions use `src = ./.`, which would copy its 22 GiB
        # Cargo `target/` into the store (and, through the derivations
        # src/vulnix.nix ships, onto tower). Import a copy without build
        # output and VCS data instead; its `./.` then refers to that copy.
        agameSrc = lib.cleanSourceWith {
          name = "agame-source";
          src = ../../agame;
          filter =
            path: type:
            !(builtins.elem (baseNameOf path) [
              "target"
              "result"
              ".git"
              ".jj"
              ".direnv"
            ]);
        };
        agame = import "${agameSrc}" { }; # TODO
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
