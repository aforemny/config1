{ config, sources, ... }: {
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
