{
  # i run impermanent home and keep all my permanent stuff in `~/s`
  homeManagerModules.home-persistence =
    { osConfig, lib, ... }:
    lib.mkIf (osConfig.tags.graphical or false) {
      state.directories = [ "s" ];
    };
}
