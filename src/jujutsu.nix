{ config, sources, ... }:
{
  nixosModules.jujutsu =
    { pkgs, ... }:
    let
      inherit (import sources.wrappers { inherit pkgs; }) wrapperModules;
    in
    {
      environment.systemPackages = [
        (wrapperModules.git.apply {
          inherit pkgs;
          settings.user = {
            name = "Alexander Foremny";
            email = "aforemny@posteo.de";
          };
        }).wrapper
        (wrapperModules.jujutsu.apply {
          inherit pkgs;
          settings = {
            name = "Alexander Foremny";
            email = "aforemny@posteo.de";
          };
        }).wrapper
      ];
    };
}
