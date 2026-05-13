{ lib, pkgs, ... }:
{
  _cake.cake-cli.cake-run-vm.preStart = ''
    secrets="$tmp"/secrets
    ASECRET_OUT="$secrets" ${lib.getExe pkgs.asecret} export
    QEMU_OPTS="''${QEMU_OPTS:+$QEMU_OPTS }"'-virtfs local,path='"$secrets"',security_model=mapped-xattr,mount_tag=secrets'
    export QEMU_OPTS
  '';
  nixosModules.vm-variant =
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
                options = [ "mode=755" ];
              };
              "/persist" = {
                device = "/dev/disk/by-label/nixos";
                fsType = "ext4";
                autoFormat = true;
                neededForBoot = true;
              };
              "/var/src/secrets" = {
                device = "secrets";
                fsType = "9p";
                neededForBoot = true;
                options = [
                  "trans=virtio"
                  "version=9p2000.L"
                  "msize=16384"
                  "x-systemd.requires=modprobe@9pnet_virtio.service"
                ];
              };
            };
          };
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
