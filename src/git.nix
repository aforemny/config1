{
  homeManagerModules.git =
    { lib, ... }:
    lib.mkMerge [
      {
        programs.git = {
          enable = true;
          ignores = [ "*~" ];
          signing.format = null;
          settings.user.rebase.autoStash = true;
        };
      }
      {
        programs.git.settings.user = {
          name = "Alexander Foremny";
          email = "aforemny@posteo.de";
        };
      }
    ];
}
