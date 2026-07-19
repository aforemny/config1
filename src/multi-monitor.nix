{
  nixosModules.multi-monitor =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (config.tags.graphical or false) {
      environment.systemPackages = with pkgs; [
        moonlight-qt
        wayvnc
      ];
      programs.niri.config.settings.outputs.x1e = {
        mode = "3840x2160@60.002";
        scale = 2;
      };
      services.sunshine = {
        enable = true;
        autoStart = true;
        capSysAdmin = true;
      };
      hardware.uinput.enable = true;
      users.users.aforemny.extraGroups = [
        "input"
        "uinput"
      ];
    };
}
