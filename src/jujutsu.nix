{ config, sources, ... }:
{
  nixosModules.jujutsu =
    { pkgs, ... }:
    let
      inherit (import sources.wrappers { inherit pkgs; }) wrapperModules;
    in
    {
      environment.systemPackages = [
        (wrapperModules.jujutsu.apply {
          inherit pkgs;
          settings.user = {
            name = "Alexander Foremny";
            email = "aforemny@posteo.de";
          };
        }).wrapper
      ];
    };
  # Per-repo config (`jj config edit --repo`) and its metadata live outside
  # the repo, keyed by repo id.
  homeManagerModules.jujutsu = {
    state.directories = [ ".config/jj/repos" ];
  };
}
