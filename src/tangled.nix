{ sources, ... }:
let
  # Upstream's flake, through the flake-compat default.nix it ships.
  tangled = import sources.tangled;
in
{
  # A tangled.org knot at https://knot.nomath.org: tower hosts the git
  # repositories, and the tangled.org web app shows them. The knot keeps no
  # user database: it knows people by their atproto DID, and admins by
  # settings.server.admins below. Add the knot under Settings -> Knots in the
  # web app.
  #
  # SSH. tower's own sshd keeps port 22, so the knot's git-over-SSH listens on
  # 2222 (opened by the module). The web app's SSH clone URLs assume port 22;
  # use ssh://git@knot.nomath.org:2222/... or a Port entry in ~/.ssh/config.
  #
  # STATE. /var/lib/knot holds the repositories, the sealed key store and the
  # SSH host key. The sealed keys are useless without KNOT_MASTER_KEY, which is
  # the knot-env secret below; both together are every repository's identity.
  #
  # CI. A spindle at https://spindle.nomath.org runs .tangled/workflows/*.yml;
  # pick it per repository under Settings -> Pipelines in the web app. It
  # serves only the owner below and DIDs added with `spindle allowlist add`.
  # Workflows need `engine: microvm`: the nixery engine needs Docker and the
  # nixery.tangled.sh image service, and neither is set up here. Secrets and
  # logs stay in /var/lib/spindle and /var/log/spindle.
  systems.tower.modules = [
    tangled.nixosModules.knot-rs
    tangled.nixosModules.spindle
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "knot.nomath.org";
        port = 5555;
        owner = "did:plc:nrbyhbnlvjbyplyw5vpnoghn"; # aforemny.tngl.sh
        spindleFqdn = "spindle.nomath.org";
        spindlePort = 6555;
      in
      {
        age.secrets.knot-env.generator.script =
          { pkgs, ... }:
          "printf 'KNOT_MASTER_KEY=%s\\n' \"$(${pkgs.openssl}/bin/openssl rand -base64 32)\"";

        services.tangled.knot-rs = {
          enable = true;
          environmentFile = config.age.secrets.knot-env.path;
          settings = {
            server = {
              hostname = fqdn;
              admins = [ owner ];
              listen_addr = "127.0.0.1:${toString port}";
            };
            atproto.plc_directory = "https://plc.directory";
            contact.email = "aforemny@nomath.org";
            # Existing SHA-1 repositories (GitHub and most others) cannot be
            # pushed into these; they need converting first. It only applies
            # to repositories created after it is set.
            git.object_format = "sha256";
            # nginx is the only HTTP client; take the client address from it.
            xrpc = {
              trusted_proxy_header = "x-forwarded-for";
              trusted_proxies = [ "127.0.0.1" ];
            };
          };
        };

        # The spindle's identity: the public half goes into its did:web
        # document. It never makes one itself, and losing it makes the web app
        # distrust the spindle for a while.
        age.secrets.spindle-key.generator.script =
          { pkgs, ... }: "${pkgs.openssl}/bin/openssl ecparam -name prime256v1 -genkey -noout";

        services.tangled.spindle = {
          enable = true;
          keyPath = config.age.secrets.spindle-key.path;
          contact.email = "aforemny@nomath.org";
          server = {
            hostname = spindleFqdn;
            inherit owner;
            listenAddr = "127.0.0.1:${toString spindlePort}";
          };
          # Logs stay on disk, in /var/log/spindle, rather than in S3.
          artifactStores.s3.bucket = "";
          pipelines = {
            # The default 5m is too short for Nix builds.
            workflowTimeout = "1h";
            # tower has 16 GiB and serves Jellyfin, Home Assistant and the
            # rest: room for two 4 GiB VMs, or one large-image VM.
            microvm.limits.total = {
              memoryMiB = 8192;
              vcpus = 6;
            };
          };
        };

        # Only the microvm engine is used; see CI above. Docker would also put
        # its storage on the rollback rootfs.
        virtualisation.docker.enable = lib.mkForce false;

        systemd.tmpfiles.rules = [
          "L+ /var/lib/spindle/images/nixos - - - - ${
            tangled.packages.${pkgs.stdenv.hostPlatform.system}.spindle-nixos-image
          }"
        ];

        services.nginx = {
          enable = true;
          virtualHosts.${spindleFqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString spindlePort}";
              proxyWebsockets = true; # live logs
              recommendedProxySettings = true;
              extraConfig = ''
                proxy_buffering off;
              '';
            };
          };
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              proxyWebsockets = true; # subscribeRepos event stream
              recommendedProxySettings = true;
              extraConfig = ''
                client_max_body_size 0; # git pushes and LFS uploads
                proxy_buffering off;
                proxy_request_buffering off;
              '';
            };
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Published as knot.nomath.org and spindle.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [
          "knot"
          "spindle"
        ];

        # Created via tmpfiles, not StateDirectory=, so a bare state.directories
        # string would be root:root (same reasoning as src/jellyfin.nix).
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/knot";
            user = "knot";
            group = "knot";
            mode = "0750";
          }
        ];

        # The spindle runs as root and gets these from StateDirectory= and
        # LogsDirectory=, so bare strings are fine.
        state.directories = [
          "/var/lib/spindle"
          "/var/log/spindle"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
