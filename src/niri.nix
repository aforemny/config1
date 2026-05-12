{ config, ... }:
{
  nixosModules.niri =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        alacritty
        brightnessctl
        fuzzel
        playerctl
        swaylock
      ];
      programs = {
        niri.enable = true;
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
  _systems.defaultModules = [
    # TODO
    #config.nixosModules.niri
    #{
    #  virtualisation.vmVariant.virtualisation.qemu.options = [
    #    "-device virtio-vga"
    #  ];
    #}
    #{
    #  services.xserver.enable = true;
    #  services.xserver.displayManager.gdm.enable = true;
    #  services.xserver.desktopManager.gnome.enable = true;
    #}
  ];
}
