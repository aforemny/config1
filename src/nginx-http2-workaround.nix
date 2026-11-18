{ ... }:
{
  # Workaround for CVE-2026-123633 / CVE-2026-123007 (nginx HTTP/2 RCE,
  # https://www.wiz.io/blog/nginx-http2-rce-vulnerabilities): disable HTTP/2
  # on every vhost until nixpkgs ships nginx >= 1.30.7. The module emits a
  # per-server `http2 on;`, so an http-level `http2 off;` would not suffice.
  # Remove this file once the nixpkgs pin has nginx 1.30.7.
  nixosModules.nginx-http2-workaround =
    { lib, ... }:
    {
      options.services.nginx.virtualHosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule { http2 = lib.mkForce false; });
      };
    };
}
