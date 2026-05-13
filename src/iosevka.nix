{
  nixosModules.iosevka =
    { lib, pkgs, ... }:
    {
      options.systemFont = {
        font_family = lib.mkOption {
          type = lib.types.str;
        };
        font_size = lib.mkOption {
          type = lib.types.int;
        };
      };
      config = {
        fonts.packages = with pkgs; [
          nerd-fonts.iosevka-term
        ];
        systemFont = {
          font_family = "IosevkaTerm Nerd Font";
          #font_size = 22;
        };
      };
    };
}
