{
  config,
  lib,
  sources,
  ...
}:
{
  nixosModules.persistence =
    { config, ... }:
    let
      cfg = config.environment.persistence."/persist";
    in
    {
      config = lib.mkMerge [
        {
          environment.persistence."/persist" = {
            # Two independent modules may legitimately persist the same path
            # (e.g. radicle and keycloak both need /var/lib/acme); impermanence
            # rejects exact duplicates, so collapse them here.
            directories = lib.mkIf cfg.enable (lib.unique config.state.directories);
            files = lib.mkIf cfg.enable (lib.unique config.state.files);
          };
        }
        {
          environment.persistence."/persist" = {
            directories = lib.mkIf cfg.enable [ "/var/lib/nixos" ];
            # The rollback root wipes /etc on every boot; unless machine-id is
            # persisted it is regenerated each boot, which reshuffles everything
            # derived from it -- notably systemd-networkd's `persistent` MAC (so
            # bridge MACs churn) and the DHCP DUID -- so DHCP leases and IPs move
            # on every reboot.
            files = lib.mkIf cfg.enable [ "/etc/machine-id" ];
          };
        }
      ];
    };
  _systems.defaultModules = [ "${sources.impermanence}/nixos.nix" ];
  homeManagerModules.persistence =
    { osConfig, config, ... }:
    let
      cfg = osConfig.environment.persistence."/persist";
    in
    {
      home.persistence."/persist" = {
        directories = lib.mkIf cfg.enable config.state.directories;
        files = lib.mkIf cfg.enable config.state.files;
      };
    };
}
