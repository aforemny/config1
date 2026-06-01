{ config, sources, ... }:
{
  nixosModules.niri =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (import sources.wrappers { inherit pkgs; }) wrapperModules;
    in
    lib.mkIf (config.tags.graphical or false) {
      environment.systemPackages = with pkgs; [
        alacritty
        brightnessctl
        fuzzel
        playerctl
        swaylock
        wl-clipboard
        xwayland-satellite
      ];
      programs = {
        niri = {
          enable = true;
          package =
            (wrapperModules.niri.apply {
              inherit pkgs;
              settings.binds = {
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
            }).wrapper;
        };
        dms-shell.enable = true;
      };
      services = {
        displayManager.dms-greeter = {
          enable = true;
          compositor.name = "niri";
        };
        iio-niri = {
          enable = true;
        };
      };
    };
}
