{
  nixosModules.direnv =
    { config, lib, ... }:
    lib.mkIf config.tags.graphical {
      programs.direnv.enable = true;
    };
  homeManagerModules.direnv =
    { config, lib, ... }:
    lib.mkIf config.tags.graphical {
      state.directories = [ ".local/share/direnv" ];
    };
}
