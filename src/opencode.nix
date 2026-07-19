{ sources, ... }:
{
  homeManagerModules.opencode =
    { osConfig, lib, ... }:
    lib.mkIf (osConfig.networking.hostName == "tower") {
      programs.opencode = {
        enable = true;
        settings.autoupdate = false;
      };
      state.directories = [ ".local/share/opencode" ];
    };

  systems.tower.modules = [
    (
      { config, pkgs, ... }:
      let
        fqdn = "opencode.nomath.org";
        port = 8787;
      in
      {
        imports = [ "${sources."opencode-nix"}/nix/nixos/module.nix" ];
        age.secrets.opencode-main-env.generator.script =
          { pkgs, ... }:
          ''
            echo "ANTHROPIC_API_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 32)"
            echo "OPENCODE_SERVER_PASSWORD=$(${pkgs.openssl}/bin/openssl rand -hex 16)"
          '';

        services.opencode = {
          enable = true;
          instances.main = {
            package = pkgs.opencode;
            directory = "/srv/opencode/main";
            stateDir = "/var/lib/opencode/instance-state/main";
            listen = {
              address = "127.0.0.1";
              inherit port;
            };
            environmentFile = config.age.secrets.opencode-main-env.path;
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
                proxy_buffering off;
                proxy_read_timeout 3600s;
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

        dns.dynamicAAAA = [ "opencode" ];

        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/opencode/instance-state/main";
            user = "opencode-main";
            group = "opencode";
            mode = "0750";
          }
          {
            directory = "/srv/opencode/main";
            user = "opencode-main";
            group = "opencode";
            mode = "0750";
          }
        ];

        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
