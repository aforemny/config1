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
      config = lib.mkMerge [
        {
          environment.systemPackages = [
            config.programs.kitty.package
          ];
        }
        {
          programs.kitty = {
            enable = true;
            package =
              (wrapperModules.kitty.apply (
                #lib.mkMerge [
                {
                  inherit pkgs;
                  settings = {
                    inherit (config.systemFont) font_family; # TODO font_size;
                  };
                  #}
                  #{
                  settings = {
                    "map shift+page_up" = "scroll_page_up";
                    "map shift+page_down" = "scroll_page_down";
                  };
                  #}
                  #{
                  settings = {
                    foreground = "#${config.colorscheme.colors.base05}";
                    background = "#${config.colorscheme.colors.base00}";
                    cursorColor = "#${config.colorscheme.colors.base05}";
                    color0 = "#${config.colorscheme.colors.base00}";
                    color1 = "#${config.colorscheme.colors.base08}";
                    color2 = "#${config.colorscheme.colors.base0B}";
                    color3 = "#${config.colorscheme.colors.base0A}";
                    color4 = "#${config.colorscheme.colors.base0D}";
                    color5 = "#${config.colorscheme.colors.base0E}";
                    color6 = "#${config.colorscheme.colors.base0C}";
                    color7 = "#${config.colorscheme.colors.base05}";
                    color8 = "#${config.colorscheme.colors.base03}";
                    color9 = "#${config.colorscheme.colors.base08}";
                    color10 = "#${config.colorscheme.colors.base0B}";
                    color11 = "#${config.colorscheme.colors.base0A}";
                    color12 = "#${config.colorscheme.colors.base0D}";
                    color13 = "#${config.colorscheme.colors.base0E}";
                    color14 = "#${config.colorscheme.colors.base0C}";
                    color15 = "#${config.colorscheme.colors.base07}";
                    color16 = "#${config.colorscheme.colors.base09}";
                    color17 = "#${config.colorscheme.colors.base0F}";
                    color18 = "#${config.colorscheme.colors.base01}";
                    color19 = "#${config.colorscheme.colors.base02}";
                    color20 = "#${config.colorscheme.colors.base04}";
                    color21 = "#${config.colorscheme.colors.base06}";
                  };
                  #}
                  #{
                  settings = {
                    cursor_trail = 1;
                    cursor_trail_start_threshold = 0;
                  };
                }
                #]
              )).wrapper;
          };
        }
      ];
    };
}
