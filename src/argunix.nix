{ sources, ... }:
{
  # argunix (a declarative Nix-only CI daemon) as argunix.nomath.org, scoped
  # to tower (the public-facing host). Reverse-proxied over TLS; the daemon
  # itself only listens on loopback.
  systems.tower.modules = [
    (
      { config, lib, ... }:
      let
        fqdn = "argunix.nomath.org";
        port = 8082;
        # Read endpoint for the binary cache argunix pushes to (below). It gets
        # its own vhost: argunix's vhost reverse-proxies `/` to the daemon
        # (which already renders a `/cache` snippet page), so it cannot also
        # host the nix cache -- a dedicated host is the clean split.
        cacheHost = "cache.nomath.org";
        # file:// store argunix signs + pushes each successful closure to;
        # nginx serves this directory verbatim at https://${cacheHost}.
        cacheDir = "/var/lib/argunix-cache";
      in
      {
        imports = [ "${sources.argunix}/nix/module.nix" ];

        # `pkgs.argunix` (the module's default package) comes from argunix's
        # overlay, which `callPackage`s package.nix with `naersk` resolved
        # from the *previous* package set — so the naersk overlay MUST be
        # composed before argunix's. Keep both in this one ordered list;
        # `config.overlays` (attrValues, alphabetical) could not guarantee it.
        nixpkgs.overlays = [
          (import "${sources.naersk}/overlay.nix")
          (import "${sources.argunix}/nix/overlay.nix")
        ];

        # GitHub PAT — fine-grained with Contents:read, Commit statuses:rw,
        # Webhooks:rw, Pull requests:read (classic PAT `repo` also works).
        # Enter it with `agenix edit argunix-github-token` then `agenix rekey`.
        # Owned by the static `argunix` user so the daemon reads token_path
        # directly (the module's sandbox allows /run/agenix).
        age.secrets.argunix-github-token = {
          rekeyFile = toString ../secrets1/argunix-github-token.age;
          owner = "argunix";
          group = "argunix";
        };

        # Binary-cache signing key (nix secret-key format). Generated -- and its
        # public half committed -- by the `nix-cache-key` agenix generator (see
        # src/agenix-rekey.nix); rotate with `agenix generate -f argunix-cache-key`.
        # Owned by `argunix` so the daemon can hand its path to `nix copy
        # --to …?secret-key=` at push time.
        age.secrets.argunix-cache-key = {
          generator.script = "nix-cache-key";
          owner = "argunix";
          group = "argunix";
        };

        services.argunix = {
          enable = true;
          # Loopback only; nginx below terminates TLS and proxies in.
          listen = "127.0.0.1:${toString port}";
          settings = {
            external_url = "https://${fqdn}";
            forges.github = {
              kind = "github";
              web_url = "https://github.com";
              token_path = config.age.secrets.argunix-github-token.path;
              # Empty repo value ⇒ watch the default branch + all PRs.
              repos = {
                "aforemny/config1" = { };
                "aforemny/awebframework" = { };
              };
            };
            # Sign + push every successful build's output closure here so the
            # team substitutes instead of rebuilding. public_url + public_key
            # let the daemon render paste-ready snippets at /cache. public_key
            # is the committed public half of the signing key above.
            binary_caches = [
              {
                push_url = "file://${cacheDir}";
                public_url = "https://${cacheHost}";
                public_key = lib.fileContents ../secrets1/generated/argunix-cache-key.pub;
                signing_key_path = config.age.secrets.argunix-cache-key.path;
              }
            ];
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              recommendedProxySettings = true;
              # Forge webhook payloads (GitHub push/PR events) can exceed
              # nginx's 1 MB default; matches argunix's reference deployment.
              extraConfig = ''
                client_max_body_size 32m;
                proxy_read_timeout 120s;
              '';
            };
          };
          # Serve the file:// binary cache verbatim. Public read-only: nix
          # fetches /nix-cache-info, <hash>.narinfo and nar/* as static files.
          virtualHosts.${cacheHost} = {
            forceSSL = true;
            enableACME = true;
            root = cacheDir;
          };
        };

        # argunix runs ProtectSystem=strict with only its gcroots dir writable;
        # `nix copy --to file://${cacheDir}` writes the cache directly, so open
        # that dir too. Merges with the module's own ReadWritePaths list.
        systemd.services.argunix.serviceConfig.ReadWritePaths = [ cacheDir ];

        security.acme = {
          acceptTerms = true;
          defaults.email = "aforemny@posteo.de";
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Published as argunix.nomath.org / cache.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [
          "argunix"
          "cache"
        ];

        # `/var/lib/argunix` (sqlite DB, build logs, work dirs) is created and
        # chowned to the static `argunix` user by the unit's
        # `StateDirectory=argunix`, so a bare-string /persist bind-mount
        # self-heals across tower's rootfs rollback.
        state.directories = [
          "/var/lib/argunix"
          "/var/lib/acme"
        ];

        # cacheDir is created by neither StateDirectory= nor a module tmpfiles
        # rule, so persist it with explicit ownership: impermanence creates the
        # /persist source owned by `argunix` (mode 0755 so nginx can traverse
        # and serve it) so it survives tower's rootfs rollback.
        environment.persistence."/persist".directories = [
          {
            directory = cacheDir;
            user = "argunix";
            group = "argunix";
            mode = "0755";
          }
        ];
      }
    )
  ];
}
