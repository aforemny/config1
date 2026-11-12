{ sources, ... }:
let
  # SSH enrollment port of argunix's builder pool on tower (2222, the
  # default, is taken there).
  builderPort = 45678;

  # `pkgs.argunix` (the modules' default package) comes from argunix's
  # overlay, which `callPackage`s package.nix with `naersk` resolved from
  # the *previous* package set — so the naersk overlay MUST be composed
  # before argunix's. Keep both in this one ordered list;
  # `config.overlays` (attrValues, alphabetical) could not guarantee it.
  overlays = [
    (import "${sources.naersk}/overlay.nix")
    (import "${sources.argunix}/nix/overlay.nix")
  ];
in
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

        nixpkgs.overlays = overlays;

        # GitHub PAT — fine-grained with Contents:read, Commit statuses:rw,
        # Webhooks:rw, Pull requests:read (classic PAT `repo` also works).
        # Enter it with `agenix edit argunix-github-token` then `agenix rekey`.
        # Owned by the static `argunix` user so the daemon reads token_path
        # directly (the module's sandbox allows /run/agenix).
        age.secrets.argunix-github-token = {
          rekeyFile = toString ../secrets/argunix-github-token.age;
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

        # Shared builder-enrollment token (m1's agent presents it, see
        # below). The daemon reads token_path directly, hence owner `argunix`.
        age.secrets.argunix-builder-enrollment-token = {
          generator.script = "alnum";
          owner = "argunix";
          group = "argunix";
        };

        services.argunix = {
          enable = true;
          # Builders reach the enrollment listener over mvpn only (see the
          # interface-scoped firewall rule below), never from the internet.
          openBuilderFirewall = false;
          # The coordinator builds nothing itself; m1 is the only builder, so
          # evaluate for its system (x86_64 checks would have no builder).
          systems = [ "aarch64-linux" ];
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
            builder_enrollment = {
              # All interfaces, so the daemon needn't wait for mvpn to come up;
              # the firewall admits it on mvpn alone.
              listen = "0.0.0.0:${toString builderPort}";
              token_path = config.age.secrets.argunix-builder-enrollment-token.path;
            };
            # Wait for m1 to (re-)enroll after a reconnect instead of failing
            # jobs straight away (the default 0 fails fast).
            schedule.builder_wait_seconds = 120;
            # Sign + push every successful build's output closure here so the
            # team substitutes instead of rebuilding. public_url + public_key
            # let the daemon render paste-ready snippets at /cache. public_key
            # is the committed public half of the signing key above.
            binary_caches = [
              {
                push_url = "file://${cacheDir}";
                public_url = "https://${cacheHost}";
                public_key = lib.fileContents ../secrets/generated/argunix-cache-key.pub;
                signing_key_path = config.age.secrets.argunix-cache-key.path;
              }
            ];
          };
        };

        networking.firewall.interfaces.mvpn.allowedTCPPorts = [ builderPort ];

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

        # systemd 262 refuses to start a Type=notify-reload unit whose main
        # process has no handler for its ReloadSignal (SIGHUP), and argunix
        # installs none: it reloads through ExecReload=argunixctl reload.
        # Plain notify keeps readiness and that ExecReload.
        systemd.services.argunix.serviceConfig.Type = lib.mkForce "notify";

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Published as argunix.nomath.org / cache.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [
          "argunix"
          "cache"
        ];
        # GitHub delivers webhooks over IPv4 only, so the webhook endpoint
        # also needs an A record (apu's address, 80/443 forwarded to tower).
        dns.dynamicA = [ "argunix" ];

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

  # m1 is argunix's builder: the coordinator on tower builds nothing itself,
  # and tower is too loaded to build. The agent dials tower over mvpn, so it
  # works off the LAN too, and runs builds through m1's own nix-daemon.
  systems.m1.modules = [
    (
      { config, ... }:
      {
        imports = [ "${sources.argunix}/nix/builder-module.nix" ];
        nixpkgs.overlays = overlays;

        # Same generated token as tower's; the agent gets it through
        # LoadCredential=, which reads as root, so root ownership is fine.
        age.secrets.argunix-builder-enrollment-token.rekeyFile = ../secrets/generated/argunix-builder-enrollment-token.age;

        # One CI build at a time: m1 has 8 GB of RAM and is a desktop (see
        # systems/m1.nix). That build still gets every core.
        services.argunix-builder = {
          enable = true;
          argunixHost = "10.77.0.1"; # tower on mvpn
          argunixPort = builderPort;
          enrollmentTokenFile = config.age.secrets.argunix-builder-enrollment-token.path;
          maxJobs = 1;
        };

        # Keep the desktop responsive while CI builds run.
        nix.daemonCPUSchedPolicy = "idle";
        nix.daemonIOSchedClass = "idle";

        # Agent's ed25519 identity (enrolled pubkey); StateDirectory=
        # chowns it, so a bare-string bind-mount self-heals.
        state.directories = [ "/var/lib/argunix-builder" ];
      }
    )
  ];
}
