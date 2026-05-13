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
            directories = lib.mkIf cfg.enable config.state.directories;
            files = lib.mkIf cfg.enable config.state.files;
          };
        }
        {
          environment.persistence."/persist" = {
            directories = lib.mkIf cfg.enable [ "/var/lib/nixos" ];
          };
        }
      ];
    };
  _systems.defaultModules = [ "${sources.impermanence}/nixos.nix" ];
}
