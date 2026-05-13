{ config, ... }:
{
  nixosModules.defaults =
    { lib, ... }:
    lib.mkMerge [
      {
        users.mutableUsers = false;
      }
      {
        virtualisation = {
          vmVariant = {
            hardware.graphics.enable = true;
            services.getty.autologinUser = "root";
            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN"
            ];
            virtualisation = {
              qemu.options = [
                "-vga none"
                "-device virtio-gpu-gl"
                "-display gtk,gl=on"
              ];
              cores = 12;
              memorySize = 16 * 1024;
              resolution = {
                x = 3840;
                y = 2160;
              };
              diskImage = null;
              forwardPorts = [
                {
                  from = "host";
                  host.port = 2222;
                  guest.port = 22;
                }
              ];
            };
          };
        };
      }
    ];
}
