{ sources, ... }:
{
  nixosModules.kitty =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (import sources.wrappers { inherit pkgs; }) wrapperModules;
    in
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
              inherit (config.systemFont) font_family font_size;
            };
          }).wrapper;
      };
    };
}
