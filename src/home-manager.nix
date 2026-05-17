{
  config,
  sources,
  ...
}:
{
  nixosModules.homeManager =
    let
      inherit (config) homeManagerModules;
    in
    { config, lib, ... }:
    {
      imports = [ "${sources.home-manager}/nixos" ];
      config = {
        home-manager.users.aforemny = {
          imports = lib.attrValues homeManagerModules;
          config = {
            home.stateVersion = "25.11";
          };
        };
        #home-manager.users.root = {
        #  imports = lib.attrValues homeManagerModules;
        #  specialArgs = { osConfig = config; };
        #  config = {
        #    home.stateVersion = "25.11";
        #  };
        #};
      };
    };
}
