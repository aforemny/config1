{ config, sources, ... }:
let
  inherit (config) wrapperModules;
in
{
  nixosModules.niri =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.niri;
      niri = wrapperModules.niri.extend { inherit pkgs; };
    in
    {
      options.programs.niri.config.settings = lib.mkOption {
        type = niri.options.settings.type;
        default = { };
      };
      config = lib.mkMerge [
        {
          programs.niri = {
            enable = lib.mkDefault (config.tags.graphical or false);
            package =
              lib.mkDefault
                (niri.config.apply {
                  inherit (cfg.config) settings;
                }).wrapper;
          };
        }
        (lib.mkIf cfg.enable (
          lib.mkMerge [
            {
              environment.systemPackages = with pkgs; [
                alacritty
                brightnessctl
                fuzzel
                playerctl
                swaylock
                wl-clipboard
                xwayland-satellite
              ];
              programs.dms-shell.enable = true;
              services = {
                displayManager.dms-greeter = {
                  enable = true;
                  compositor.name = "niri";
                };
                iio-niri = {
                  enable = true;
                };
              };
            }
            {
              programs.niri.config = lib.mkMerge [
                {
                  settings = {
                    outputs.eDP-1 = {
                      scale = 2;
                    };
                    binds = {
                      "Mod+Shift+Slash".show-hotkey-overlay = null;
                      "Mod+Shift+Return" = {
                        _attrs.hotkey-overlay-title = "Open a Terminal: kitty";
                        spawn = "${lib.getExe config.programs.kitty.package}";
                      };
                      "Mod+P" = {
                        _attrs.hotkey-overlay-title = "Run an Application: fuzzel";
                        spawn = "fuzzel";
                      };
                      "Super+Alt+L" = {
                        _attrs.hotkey-overlay-title = "Lock the Screen: swaylock";
                        spawn = "swaylock";
                      };
                      "Super+Alt+S" = {
                        _attrs.allow-when-locked = true;
                        _attrs.hotkey-overlay-title = "null";
                        spawn-sh = "pkill orca || exec orca";
                      };
                      "XF86AudioRaiseVolume" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0";
                      };
                      "XF86AudioLowerVolume" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-";
                      };
                      "XF86AudioMute" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
                      };
                      "XF86AudioMicMute" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
                      };
                      "XF86AudioPlay" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "playerctl play-pause";
                      };
                      "XF86AudioStop" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "playerctl stop";
                      };
                      "XF86AudioPrev" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "playerctl previous";
                      };
                      "XF86AudioNext" = {
                        _attrs.allow-when-locked = true;
                        spawn-sh = "playerctl next";
                      };
                      "XF86MonBrightnessUp" = {
                        _attrs.allow-when-locked = true;
                        spawn = [
                          "brightnessctl"
                          "--class=backlight"
                          "set"
                          "+10%"
                        ];
                      };
                      "XF86MonBrightnessDown" = {
                        _attrs.allow-when-locked = true;
                        spawn = [
                          "brightnessctl"
                          "--class=backlight"
                          "set"
                          "10%-"
                        ];
                      };
                      "Mod+O" = {
                        _attrs.repeat = false;
                        toggle-overview = null;
                      };
                      "Mod+Shift+C" = {
                        _attrs.repeat = false;
                        close-window = null;
                      };
                      "Mod+Left".focus-column-left = null;
                      "Mod+Down".focus-window-down = null;
                      "Mod+Up".focus-window-up = null;
                      "Mod+Right".focus-column-right = null;
                      "Mod+H".focus-column-left = null;
                      "Mod+J".focus-window-down = null;
                      "Mod+K".focus-window-up = null;
                      "Mod+L".focus-column-right = null;
                      "Mod+Shift+Left".move-column-left = null;
                      "Mod+Shift+Down".move-window-down = null;
                      "Mod+Shift+Up".move-window-up = null;
                      "Mod+Shift+Right".move-column-right = null;
                      "Mod+Shift+H".move-column-left = null;
                      "Mod+Shift+J".move-window-down = null;
                      "Mod+Shift+K".move-window-up = null;
                      "Mod+Shift+L".move-column-right = null;
                      "Mod+Home".focus-column-first = null;
                      "Mod+End".focus-column-last = null;
                      "Mod+Shift+Home".move-column-to-first = null;
                      "Mod+Shift+End".move-column-to-last = null;
                      "Mod+Ctrl+Left".focus-monitor-left = null;
                      "Mod+Ctrl+Down".focus-monitor-down = null;
                      "Mod+Ctrl+Up".focus-monitor-up = null;
                      "Mod+Ctrl+Right".focus-monitor-right = null;
                      "Mod+Ctrl+H".focus-monitor-left = null;
                      "Mod+Ctrl+J".focus-monitor-down = null;
                      "Mod+Ctrl+K".focus-monitor-up = null;
                      "Mod+Ctrl+L".focus-monitor-right = null;
                      "Mod+Ctrl+Shift+Left".move-column-to-monitor-left = null;
                      "Mod+Ctrl+Shift+Down".move-column-to-monitor-down = null;
                      "Mod+Ctrl+Shift+Up".move-column-to-monitor-up = null;
                      "Mod+Ctrl+Shift+Right".move-column-to-monitor-right = null;
                      "Mod+Ctrl+Shift+H".move-column-to-monitor-left = null;
                      "Mod+Ctrl+Shift+J".move-column-to-monitor-down = null;
                      "Mod+Ctrl+Shift+K".move-column-to-monitor-up = null;
                      "Mod+Ctrl+Shift+L".move-column-to-monitor-right = null;
                      "Mod+Page_Down".focus-workspace-down = null;
                      "Mod+Page_Up".focus-workspace-up = null;
                      "Mod+U".focus-workspace-down = null;
                      "Mod+I".focus-workspace-up = null;
                      "Mod+Shift+Page_Down".move-column-to-workspace-down = null;
                      "Mod+Shift+Page_Up".move-column-to-workspace-up = null;
                      "Mod+Shift+U".move-column-to-workspace-down = null;
                      "Mod+Shift+I".move-column-to-workspace-up = null;
                      "Mod+Ctrl+Page_Down".move-workspace-down = null;
                      "Mod+Ctrl+Page_Up".move-workspace-up = null;
                      "Mod+Ctrl+U".move-workspace-down = null;
                      "Mod+Ctrl+I".move-workspace-up = null;
                      "Mod+WheelScrollDown" = {
                        _attrs.cooldown-ms = 150;
                        focus-workspace-down = null;
                      };
                      "Mod+WheelScrollUp" = {
                        _attrs.cooldown-ms = 150;
                        focus-workspace-up = null;
                      };
                      "Mod+Shift+WheelScrollDown" = {
                        _attrs.cooldown-ms = 150;
                        move-column-to-workspace-down = null;
                      };
                      "Mod+Shift+WheelScrollUp" = {
                        _attrs.cooldown-ms = 150;
                        move-column-to-workspace-up = null;
                      };
                      "Mod+WheelScrollRight".focus-column-right = null;
                      "Mod+WheelScrollLeft".focus-column-left = null;
                      "Mod+Shift+WheelScrollRight".move-column-right = null;
                      "Mod+Shift+WheelScrollLeft".move-column-left = null;
                      "Mod+Ctrl+WheelScrollDown".focus-column-right = null;
                      "Mod+Ctrl+WheelScrollUp".focus-column-left = null;
                      "Mod+Shift+Ctrl+WheelScrollDown".move-column-right = null;
                      "Mod+Shift+Ctrl+WheelScrollUp".move-column-left = null;
                      "Mod+1".focus-workspace = 1;
                      "Mod+2".focus-workspace = 2;
                      "Mod+3".focus-workspace = 3;
                      "Mod+4".focus-workspace = 4;
                      "Mod+5".focus-workspace = 5;
                      "Mod+6".focus-workspace = 6;
                      "Mod+7".focus-workspace = 7;
                      "Mod+8".focus-workspace = 8;
                      "Mod+9".focus-workspace = 9;
                      "Mod+Shift+1".move-column-to-workspace = 1;
                      "Mod+Shift+2".move-column-to-workspace = 2;
                      "Mod+Shift+3".move-column-to-workspace = 3;
                      "Mod+Shift+4".move-column-to-workspace = 4;
                      "Mod+Shift+5".move-column-to-workspace = 5;
                      "Mod+Shift+6".move-column-to-workspace = 6;
                      "Mod+Shift+7".move-column-to-workspace = 7;
                      "Mod+Shift+8".move-column-to-workspace = 8;
                      "Mod+Shift+9".move-column-to-workspace = 9;
                      "Mod+BracketLeft".consume-or-expel-window-left = null;
                      "Mod+BracketRight".consume-or-expel-window-right = null;
                      "Mod+Comma".consume-window-into-column = null;
                      "Mod+Period".expel-window-from-column = null;
                      "Mod+R".switch-preset-column-width = null;
                      "Mod+Ctrl+R".switch-preset-window-height = null;
                      "Mod+Shift+R".reset-window-height = null;
                      "Mod+F".maximize-column = null;
                      "Mod+Ctrl+F".fullscreen-window = null;
                      "Mod+Shift+F".expand-column-to-available-width = null;
                      "Mod+C".center-column = null;
                      "Mod+Ctrl+C".center-visible-columns = null;
                      "Mod+Minus".set-column-width = "-10%";
                      "Mod+Equal".set-column-width = "+10%";
                      "Mod+Ctrl+Minus".set-window-height = "-10%";
                      "Mod+Ctrl+Equal".set-window-height = "+10%";
                      "Mod+V".toggle-window-floating = null;
                      "Mod+Ctrl+V".switch-focus-between-floating-and-tiling = null;
                      "Mod+W".toggle-column-tabbed-display = null;
                      "Print".screenshot = null;
                      "Ctrl+Print".screenshot-screen = null;
                      "Alt+Print".screenshot-window = null;
                      "Mod+Escape" = {
                        _attrs.allow-inhibiting = false;
                        toggle-keyboard-shortcuts-inhibit = null;
                      };
                      "Mod+Ctrl+E".quit = null;
                      "Ctrl+Alt+Delete".quit = null;
                      "Mod+Ctrl+P".power-off-monitors = null;
                    };
                  };
                }
                {
                  # input {
                  #     keyboard {
                  #         xkb {}
                  #         numlock
                  #     }
                  #     touchpad {
                  #         tap
                  #         natural-scroll
                  #     }
                  #     mouse {}
                  #     trackpoint {}
                  #     warp-mouse-to-focus
                  # }

                  # output "eDP-1" {
                  #     mode "3840x2160@60"
                  #     scale 1
                  # }

                  # layout {
                  #     gaps 16
                  #     center-focused-column "never"
                  #     preset-column-widths {
                  #         proportion 0.33333
                  #         proportion 0.5
                  #         proportion 0.66667
                  #     }
                  #     default-column-width { proportion 0.33333; }
                  #     focus-ring {
                  #         width 4
                  #         active-color "#7fc8ff"
                  #         inactive-color "#505050"
                  #     }
                  #     border {
                  #         off
                  #         width 4
                  #         active-color "#ffc87f"
                  #         inactive-color "#505050"
                  #         urgent-color "#9b0000"
                  #     }
                  #     shadow {
                  #         softness 30
                  #         spread 5
                  #         offset x=0 y=5
                  #         color "#0007"
                  #     }
                  #     struts { }
                  # }

                  # spawn-at-startup "waybar"

                  # hotkey-overlay {
                  #     skip-at-startup
                  # }

                  # prefer-no-csd

                  # screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

                  # animations {}

                  # window-rule {
                  #     match app-id=r#"firefox$"# title="^Picture-in-Picture$"
                  #     open-floating true
                  # }

                  # binds {
                  #     Mod+Shift+Slash { show-hotkey-overlay; }
                  #     Mod+Shift+Return hotkey-overlay-title="Open a Terminal: kitty" { spawn "kitty"; }
                  #     Mod+P hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }
                  #     Super+Alt+L hotkey-overlay-title="Lock the Screen: swaylock" { spawn "swaylock"; }
                  #     Super+Alt+S allow-when-locked=true hotkey-overlay-title=null { spawn-sh "pkill orca || exec orca"; }
                  #     XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0"; }
                  #     XF86AudioLowerVolume allow-when-locked=true { spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"; }
                  #     XF86AudioMute        allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
                  #     XF86AudioMicMute     allow-when-locked=true { spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }
                  #     XF86AudioPlay        allow-when-locked=true { spawn-sh "playerctl play-pause"; }
                  #     XF86AudioStop        allow-when-locked=true { spawn-sh "playerctl stop"; }
                  #     XF86AudioPrev        allow-when-locked=true { spawn-sh "playerctl previous"; }
                  #     XF86AudioNext        allow-when-locked=true { spawn-sh "playerctl next"; }
                  #     XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "+10%"; }
                  #     XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "10%-"; }
                  #     Mod+O repeat=false { toggle-overview; }
                  #     Mod+Shift+C repeat=false { close-window; }
                  #     Mod+Left  { focus-column-left; }
                  #     Mod+Down  { focus-window-down; }
                  #     Mod+Up    { focus-window-up; }
                  #     Mod+Right { focus-column-right; }
                  #     Mod+H     { focus-column-left; }
                  #     Mod+J     { focus-window-down; }
                  #     Mod+K     { focus-window-up; }
                  #     Mod+L     { focus-column-right; }
                  #     Mod+Shift+Left  { move-column-left; }
                  #     Mod+Shift+Down  { move-window-down; }
                  #     Mod+Shift+Up    { move-window-up; }
                  #     Mod+Shift+Right { move-column-right; }
                  #     Mod+Shift+H     { move-column-left; }
                  #     Mod+Shift+J     { move-window-down; }
                  #     Mod+Shift+K     { move-window-up; }
                  #     Mod+Shift+L     { move-column-right; }
                  #     Mod+Home { focus-column-first; }
                  #     Mod+End  { focus-column-last; }
                  #     Mod+Shift+Home { move-column-to-first; }
                  #     Mod+Shift+End  { move-column-to-last; }
                  #     Mod+Ctrl+Left  { focus-monitor-left; }
                  #     Mod+Ctrl+Down  { focus-monitor-down; }
                  #     Mod+Ctrl+Up    { focus-monitor-up; }
                  #     Mod+Ctrl+Right { focus-monitor-right; }
                  #     Mod+Ctrl+H     { focus-monitor-left; }
                  #     Mod+Ctrl+J     { focus-monitor-down; }
                  #     Mod+Ctrl+K     { focus-monitor-up; }
                  #     Mod+Ctrl+L     { focus-monitor-right; }
                  #     Mod+Ctrl+Shift+Left  { move-column-to-monitor-left; }
                  #     Mod+Ctrl+Shift+Down  { move-column-to-monitor-down; }
                  #     Mod+Ctrl+Shift+Up    { move-column-to-monitor-up; }
                  #     Mod+Ctrl+Shift+Right { move-column-to-monitor-right; }
                  #     Mod+Ctrl+Shift+H     { move-column-to-monitor-left; }
                  #     Mod+Ctrl+Shift+J     { move-column-to-monitor-down; }
                  #     Mod+Ctrl+Shift+K     { move-column-to-monitor-up; }
                  #     Mod+Ctrl+Shift+L     { move-column-to-monitor-right; }
                  #     Mod+Page_Down      { focus-workspace-down; }
                  #     Mod+Page_Up        { focus-workspace-up; }
                  #     Mod+U              { focus-workspace-down; }
                  #     Mod+I              { focus-workspace-up; }
                  #     Mod+Shift+Page_Down { move-column-to-workspace-down; }
                  #     Mod+Shift+Page_Up   { move-column-to-workspace-up; }
                  #     Mod+Shift+U         { move-column-to-workspace-down; }
                  #     Mod+Shift+I         { move-column-to-workspace-up; }
                  #     Mod+Ctrl+Page_Down { move-workspace-down; }
                  #     Mod+Ctrl+Page_Up   { move-workspace-up; }
                  #     Mod+Ctrl+U         { move-workspace-down; }
                  #     Mod+Ctrl+I         { move-workspace-up; }
                  #     Mod+WheelScrollDown      cooldown-ms=150 { focus-workspace-down; }
                  #     Mod+WheelScrollUp        cooldown-ms=150 { focus-workspace-up; }
                  #     Mod+Shift+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
                  #     Mod+Shift+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

                  #     Mod+WheelScrollRight      { focus-column-right; }
                  #     Mod+WheelScrollLeft       { focus-column-left; }
                  #     Mod+Shift+WheelScrollRight { move-column-right; }
                  #     Mod+Shift+WheelScrollLeft  { move-column-left; }
                  #     Mod+Ctrl+WheelScrollDown      { focus-column-right; }
                  #     Mod+Ctrl+WheelScrollUp        { focus-column-left; }
                  #     Mod+Shift+Ctrl+WheelScrollDown { move-column-right; }
                  #     Mod+Shift+Ctrl+WheelScrollUp   { move-column-left; }
                  #     Mod+1 { focus-workspace 1; }
                  #     Mod+2 { focus-workspace 2; }
                  #     Mod+3 { focus-workspace 3; }
                  #     Mod+4 { focus-workspace 4; }
                  #     Mod+5 { focus-workspace 5; }
                  #     Mod+6 { focus-workspace 6; }
                  #     Mod+7 { focus-workspace 7; }
                  #     Mod+8 { focus-workspace 8; }
                  #     Mod+9 { focus-workspace 9; }
                  #     Mod+Shift+1 { move-column-to-workspace 1; }
                  #     Mod+Shift+2 { move-column-to-workspace 2; }
                  #     Mod+Shift+3 { move-column-to-workspace 3; }
                  #     Mod+Shift+4 { move-column-to-workspace 4; }
                  #     Mod+Shift+5 { move-column-to-workspace 5; }
                  #     Mod+Shift+6 { move-column-to-workspace 6; }
                  #     Mod+Shift+7 { move-column-to-workspace 7; }
                  #     Mod+Shift+8 { move-column-to-workspace 8; }
                  #     Mod+Shift+9 { move-column-to-workspace 9; }
                  #     Mod+BracketLeft  { consume-or-expel-window-left; }
                  #     Mod+BracketRight { consume-or-expel-window-right; }
                  #     Mod+Comma  { consume-window-into-column; }
                  #     Mod+Period { expel-window-from-column; }
                  #     Mod+R { switch-preset-column-width; }
                  #     Mod+Ctrl+R { switch-preset-window-height; }
                  #     Mod+Shift+R { reset-window-height; }
                  #     Mod+F { maximize-column; }
                  #     Mod+Ctrl+F { fullscreen-window; }
                  #     Mod+Shift+F { expand-column-to-available-width; }
                  #     Mod+C { center-column; }
                  #     Mod+Ctrl+C { center-visible-columns; }
                  #     Mod+Minus { set-column-width "-10%"; }
                  #     Mod+Equal { set-column-width "+10%"; }
                  #     Mod+Ctrl+Minus { set-window-height "-10%"; }
                  #     Mod+Ctrl+Equal { set-window-height "+10%"; }
                  #     Mod+V       { toggle-window-floating; }
                  #     Mod+Ctrl+V { switch-focus-between-floating-and-tiling; }
                  #     Mod+W { toggle-column-tabbed-display; }
                  #     Print { screenshot; }
                  #     Ctrl+Print { screenshot-screen; }
                  #     Alt+Print { screenshot-window; }
                  #     Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
                  #     Mod+Ctrl+E { quit; }
                  #     Ctrl+Alt+Delete { quit; }
                  #     Mod+Ctrl+P { power-off-monitors; }
                  # }
                }
              ];
            }
          ]
        ))
      ];
    };
}
