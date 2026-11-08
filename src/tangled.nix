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
  systems.tower.modules = [
    tangled.nixosModules.knot-rs
    (
      { config, ... }:
      let
        fqdn = "knot.nomath.org";
        port = 5555;
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
              admins = [ "did:plc:nrbyhbnlvjbyplyw5vpnoghn" ]; # aforemny.tngl.sh
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

        services.nginx = {
          enable = true;
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

        # Published as knot.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "knot" ];

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

        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
