{ config, sources, ... }:
let
  inherit (config) wrapperModules;
in
{
  nixosModules.kitty =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.programs.kitty = {
        enable = lib.mkEnableOption "Kitty Terminal Emulator";
        package = lib.mkPackageOption pkgs "kitty" { };
      };
      config.programs.kitty = {
        enable = true;
        package =
          (wrapperModules.kitty.apply {
            inherit pkgs;
            settings = {
              inherit (config.systemFont) font_family; # TODO font_size;
            };
          }).wrapper;
      };
    };
}
