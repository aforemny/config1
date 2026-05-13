{
  nixosModules.vmVariant =
    { config, lib, ... }:
    lib.mkMerge [
      {
        virtualisation.vmVariant = {
          virtualisation = {
            cores = 12;
            memorySize = 16 * 1024;
            #resolution = {
            #  x = 3840;
            #  y = 2160;
            #};
          };
        };
      }
      {
        virtualisation.vmVariant = {
          hardware.graphics.enable = true;
          virtualisation = {
            qemu.options = [
              "-vga none"
              "-device virtio-gpu-gl"
              "-display gtk,gl=on"
            ];
          };
        };
      }
      {
        virtualisation.vmVariant = {
          virtualisation = {
            fileSystems = {
              "/" = {
                device = lib.mkForce "tmpfs";
                fsType = lib.mkForce "tmpfs";
              };
              "/persist" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
                autoFormat = true;
                neededForBoot = true;
              };
            };
          };
        };
      }
      {
        virtualisation.vmVariant = {
          services.getty.autologinUser = "root";
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN"
          ];
        };
      }
      {
        virtualisation.vmVariant.virtualisation.forwardPorts = [
          {
            from = "host";
            host.port = 2222;
            guest.port = 22;
          }
        ];
      }
    ];
}
