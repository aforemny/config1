{
  nixosModules.direnv =
    { config, lib, ... }: lib.mkIf config.tags.graphical { programs.direnv.enable = true; };
}
