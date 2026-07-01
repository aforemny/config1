{
  nixosModules.direnv =
    { config, lib, ... }:
    lib.mkIf (config.tags.graphical or false) {
      programs.direnv.enable = true;
    };
  homeManagerModules.direnv =
    { config, lib, ... }:
    lib.mkIf (config.tags.graphical or false) {
      state.directories = [ ".local/share/direnv" ];
    };
}
