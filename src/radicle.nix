{
  # Client tooling (`rad`, `radicle-node`, `git-remote-rad`) on every graphical
  # machine, so personal identities can publish/clone against the seed.
  nixosModules.radicle =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (config.tags.graphical or false) {
      environment.systemPackages = [ pkgs.radicle-node ];
    };

  homeManagerModules.radicle =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (osConfig.tags.graphical or false) {
      state.directories = [ ".radicle" ];
    };

  # Seed node + HTTP gateway + web explorer, scoped to tower.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "radicle.nomath.org";
        # Static SPA pointed at our own seed's HTTP API.
        explorer = pkgs.radicle-explorer.withConfig {
          preferredSeeds = [
            {
              hostname = fqdn;
              port = 443;
              scheme = "https";
            }
          ];
        };
      in
      {
        # Node identity: the private key is generated and rekeyed via
        # agenix-rekey using the shared `ssh-ed25519-pub` generator (defined in
        # agenix-rekey.nix), which also writes the committed public key
        # referenced below. Rotate with `agenix generate -f radicle-node-key`.
        age.secrets.radicle-node-key.generator.script = "ssh-ed25519-pub";

        services.radicle = {
          enable = true;
          privateKey = config.age.secrets.radicle-node-key.path;
          publicKey = lib.fileContents ../secrets1/generated/radicle-node-key.pub;
          node.openFirewall = true;
          # nginx is configured manually below (the explorer owns `/`, the API is
          # mounted under `/api`), so `httpd.nginx` stays null and we set the
          # public node identity it would otherwise derive ourselves.
          settings.node = {
            alias = fqdn;
            externalAddresses = [ "${fqdn}:8776" ];
          };
          httpd.enable = true;
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            # Radicle Explorer single-page app.
            root = explorer;
            locations."/".tryFiles = "$uri $uri/ /index.html";
            # radicle-httpd JSON API: the explorer and external clients call
            # https://${fqdn}/api/v1/... (no trailing slash on proxyPass so the
            # `/api` prefix is preserved for the daemon).
            locations."/api/" = {
              proxyPass = "http://127.0.0.1:8080";
              recommendedProxySettings = true;
            };
            # radicle-httpd raw blob endpoint, used by the explorer for README
            # images, "view raw" links, etc.: https://${fqdn}/raw/<rid>/<sha>/<path>
            locations."/raw/" = {
              proxyPass = "http://127.0.0.1:8080";
              recommendedProxySettings = true;
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

        # Published as radicle.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "radicle" ];

        state.directories = [
          "/var/lib/radicle"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
