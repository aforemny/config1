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
      # No fixed release yet, and it needs a breaking protocol change. Node
      # traffic is unencrypted and Node IDs can be spoofed, which exposes private
      # repositories, so publish public ones only. See
      # https://radicle.dev/2026/09/23/disclosure-of-vulnerability-in-network-protocol
      nixpkgs.config.permittedInsecurePackages = [ "radicle-node-1.10.3" ];
      environment.systemPackages = with pkgs; [
        radicle-node
        # Hydra builds nothing that depends on an insecure package, so this is
        # built here on every update, and its unit tests assert wall-clock
        # limits (500 ms, 5 s) that fail when the machine is busy building.
        (radicle-desktop.overrideAttrs { doCheck = false; })
      ];
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
      lib.mkMerge [
        (
          let
            fqdn = "radicle.nomath.org";
          in
          {
            # Node identity: the private key is generated and rekeyed via
            # agenix-rekey using the shared `ssh-ed25519-pub` generator (defined in
            # agenix-rekey.nix), which also writes the committed public key
            # referenced below. Rotate with `agenix generate -f radicle-node-key`.
            age.secrets.radicle-node-key.generator.script = "ssh-ed25519-pub";

            # See the note on nixosModules.radicle above.
            nixpkgs.config.permittedInsecurePackages = [ "radicle-node-1.10.3" ];

            services.radicle = {
              enable = true;
              privateKey = config.age.secrets.radicle-node-key.path;
              publicKey = lib.fileContents ../secrets/generated/radicle-node-key.pub;
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
        (
          let
            fqdn = "radicle-ci.nomath.org";
            cacheDir = "/var/lib/argunix-cache"; # keep in sync with argunix.nix
            nixSocket = "/run/nix-daemon-ci/socket";
            cachePush = pkgs.writeShellScript "radicle-ci-cache-push" ''
              set -efu
              exec ${config.nix.package}/bin/nix --extra-experimental-features nix-command \
                copy --to "file://${cacheDir}?secret-key=${config.age.secrets.argunix-cache-key.path}" $OUT_PATHS
            '';
          in
          {
            services.radicle.ci = {
              broker = {
                enable = true;
                settings.triggers = [
                  {
                    adapter = "native";
                    filters = [
                      {
                        And = [
                          { HasFile = ".radicle/native.yaml"; }
                          "AnyDelegate"
                          {
                            Or = [
                              "DefaultBranch"
                              "PatchCreated"
                              "PatchUpdated"
                            ];
                          }
                        ];
                      }
                    ];
                  }
                ];
              };
              adapters.native.instances.native = {
                runtimePackages = [ pkgs.nix ];
                settings = {
                  base_url = "https://${fqdn}/native";
                  log = "/var/log/radicle-ci/native.log";
                };
              };
            };

            systemd.services.radicle-ci-broker.serviceConfig.UMask = lib.mkForce "0022";

            # CI builds go through a Nix daemon of their own, whose post-build hook
            # signs and pushes the outputs to the binary cache. In nix.conf the hook
            # would run for every build on tower: home-manager's user environments
            # were published, too, and pushing them timed out its units on boot.
            # The hook runs as root in the daemon, so CI jobs never see the key.
            services.radicle.ci.broker.settings.adapters.native.env.NIX_REMOTE = "unix://${nixSocket}";

            systemd.sockets.nix-daemon-ci = {
              description = "Nix Daemon Socket for Radicle CI";
              wantedBy = [ "sockets.target" ];
              listenStreams = [ nixSocket ];
              socketConfig = {
                SocketUser = "radicle";
                SocketMode = "0600";
              };
            };

            systemd.services.nix-daemon-ci = {
              description = "Nix Daemon for Radicle CI";
              requires = [ "nix-daemon-ci.socket" ];
              path = [
                config.nix.package
                config.programs.ssh.package
              ];
              environment = {
                inherit (config.systemd.services.nix-daemon.environment) CURL_CA_BUNDLE;
                NIX_CONFIG = "post-build-hook = ${cachePush}";
              };
              unitConfig.RequiresMountsFor = [
                "/nix/store"
                "/nix/var"
                cacheDir
              ];
              serviceConfig = {
                ExecStart = "${config.nix.package}/bin/nix-daemon --daemon";
                # As in nix-daemon.service: don't kill running builds.
                KillMode = "process";
                LimitNOFILE = 1048576;
                TasksMax = 1048576;
                Delegate = true;
              };
            };

            services.nginx = {
              enable = true;
              virtualHosts.${fqdn} = {
                forceSSL = true;
                enableACME = true;
                root = "/var/lib/radicle-ci/reports";
                locations."/native/".alias = "/var/lib/radicle-ci/adapters/native/native/";
              };
            };

            dns.dynamicAAAA = [ "radicle-ci" ];

            state.directories = [
              "/var/lib/radicle-ci"
              "/var/log/radicle-ci"
            ];
          }
        )
      ]
    )
  ];
}
