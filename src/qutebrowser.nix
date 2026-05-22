{
  nixosModules.qutebrowser = (
    { lib, ... }:
    {
      nixpkgs.config.allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "widevine-cdm"
        ];
    }
  );
  homeManagerModules.qutebrowser =
    {
      config,
      lib,
      name,
      osConfig,
      pkgs,
      ...
    }:
    {
      imports = [
        (
          let
            cfg = config.programs.qutebrowser;
          in
          {
            options.programs.qutebrowser.userScripts = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule (
                  { name, ... }:
                  {
                    options = {
                      name = lib.mkOption {
                        type = lib.types.str;
                        default = name;
                      };
                      enable = lib.mkOption {
                        type = lib.types.bool;
                        default = true;
                      };
                      src = lib.mkOption {
                        type = lib.types.path;
                        default = "${cfg.package}/share/qutebrowser/userscripts/${name}";
                      };
                    };
                  }
                )
              );
              default = { };
            };
            config = lib.mkIf cfg.enable {
              home.file = lib.mapAttrs' (
                name: userScript:
                lib.nameValuePair "${config.home.homeDirectory}/.local/share/qutebrowser/userscripts/${name}" {
                  inherit (userScript) enable;
                  source = userScript.src;
                }
              ) cfg.userScripts;
            };
          }
        )
      ];
      config = lib.mkMerge [
        {
          programs.qutebrowser = {
            enable = true;
            package = pkgs.qutebrowser.override {
              enableWideVine = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
            };
            settings = {
              fonts = {
                default_family = "IosevkaTerm Nerd Font";
               #default_size = "28px";
               #web.size = {
               #  default = 16;
               #  default_fixed = 16;
               #};
              };
              #qt.highdpi = true;
              tabs.tabs_are_windows = true;
              #zoom.default = "175%";
            };
          };
          state.directories = [ ".config/qutebrowser" ];
        }
        {
          programs.qutebrowser.searchEngines = {
            g = "https://github.com/search?q={}";
          };
        }
        {
          programs.qutebrowser.keyBindings = {
            normal = {
              "<Ctrl-v>" = "spawn mpv {url}";
              ",l" = ''config-cycle spellcheck.languages ["de-DE"] ["en-US"]'';
              "<F1>" = lib.mkMerge [
                "config-cycle tabs.show never always"
                "config-cycle statusbar.show in-mode always"
                "config-cycle scrolling.bar never always"
              ];
            };
            prompt = {
              "<Ctrl-y>" = "prompt-yes";
            };
          };
        }
        {
          programs.qutebrowser = {
            userScripts.qute-pass.enable = true;
            keyBindings.normal = {
              ",p" = "spawn --userscript qute-pass --username-pattern '[uU]sername: ?(.*)' --username-target secret";
              ",up" = "spawn --userscript qute-pass --username-only";
              ",pp" = "spawn --userscript qute-pass --password-only";
              ",op" = "spawn --userscript qute-pass --otp-only";
            };
          };
          programs.rofi.enable = true;
        }
        # TODO colorscheme
        #{
        #  programs.qutebrowser.extraConfig = builtins.readFile (
        #    pkgs.runCommand "config.py"
        #      (lib.mapAttrs' (name: lib.nameValuePair "${name}_hex") config.colorscheme.colors)
        #      ''
        #        cat ${
        #          pkgs.fetchurl {
        #            url = "https://raw.githubusercontent.com/tinted-theming/base16-qutebrowser/9e16ab2c6f090197341eec2d65faae4803928153/templates/default.mustache";
        #            hash = "sha256-l8dNIg0D97f9W+NcaMYxxi8kxEIsg/1zpztlyWvS1WY=";
        #          }
        #        } |
        #        sed 's/{{base\(..\)-hex}}/{{base\1_hex}}/g' |
        #        ${lib.getExe pkgs.mo} >$out
        #      ''
        #  );
        #}
      ];
    };
}
