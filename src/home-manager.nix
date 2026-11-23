{ config, sources, ... }:
{
  nixosModules.homeManager =
    let
      inherit (config) homeManagerModules;
    in
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ "${sources.home-manager}/nixos" ];
      config = {
        home-manager = {
          useGlobalPkgs = true;
          # Install packages with the system closure. Otherwise activation builds a
          # user environment on boot, within home-manager-<user>.service's timeout.
          useUserPackages = true;
          users = {
            aforemny = {
              imports = lib.attrValues homeManagerModules;
              config.home.stateVersion = "25.11";
            };
            root = {
              imports = lib.attrValues homeManagerModules;
              config.home.stateVersion = "25.11";
            };
          };
        };
      };
    };
}
