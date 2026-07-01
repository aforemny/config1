{
  platforms.ap =
    { config, lib, ... }:
    {
      imports = [
        {
          disko.devices.disk.main.device = "/dev/disk/by-id/ata-KINGSTON_SUV500MS120G_50026B77838C1490";
        }
      ];
      fileSystems."/persist".neededForBoot = true;
      hardware.facter = {
        enable = true;
        reportPath = ./ap.json;
      };
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      hardware.enableRedistributableFirmware = true;
      system.stateVersion = "25.11";
      boot = {
        kernelParams = [ "console=ttyS0,115200n8" ];
        loader = {
          systemd-boot.enable = false;
          grub = {
            enable = true;
            extraConfig = ''
              serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
              terminal_input serial
              terminal_output serial
            '';
          };
        };
      };
      disko.devices = {
        disk = {
          main = {
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                boot = {
                  size = "1M";
                  type = "EF02"; # for grub MBR
                };
                ESP = {
                  size = "1G";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    mountOptions = [ "umask=0077" ];
                  };
                };
                encryptedSwap = {
                  size = "4G";
                  content = {
                    type = "swap";
                    randomEncryption = true;
                  };
                };
                zfs = {
                  size = "100%";
                  content = {
                    type = "zfs";
                    pool = "zroot";
                  };
                };
              };
            };
          };
        };
        zpool = {
          zroot = {
            type = "zpool";
            rootFsOptions = {
              acltype = "posixacl";
              atime = "off";
              compression = "zstd";
              mountpoint = "none";
              xattr = "sa";
              #encryption = "aes-256-gcm";
              #keyformat = "passphrase";
              #keylocation = "prompt";
            };
            options = {
              ashift = "12";
            };
            datasets = {
              "local" = {
                type = "zfs_fs";
                options.mountpoint = "none";
                options."com.sun:auto-snapshot" = "false";
              };
              "local/nix" = {
                type = "zfs_fs";
                mountpoint = "/nix";
              };
              "local/root" = {
                type = "zfs_fs";
                mountpoint = "/";
                postCreateHook = "zfs list -t snapshot -H -o name | grep -E '^zroot/local/root@blank$' || zfs snapshot zroot/local/root@blank";
              };
              "safe" = {
                type = "zfs_fs";
                options.mountpoint = "none";
                options."com.sun:auto-snapshot" = "true";
              };
              "safe/persist" = {
                type = "zfs_fs";
                mountpoint = "/persist";
              };
            };
          };
        };
      };
    };
}
