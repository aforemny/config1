{
  platforms.ap =
    { config, lib, ... }:
    {
      # `ap` is a second apu4d4, identical hardware to `apu`. Until it is
      # installed, `ap.json` is a copy of apu's facter report (same board, so
      # the same NICs -- enp1s0..enp4s0, wlp5s0 -- and drivers). Regenerate it
      # on the target after the first boot: `nixos-facter -o /root/ap.json`,
      # copy it over this file, then rebuild.
      imports = [
        {
          # TODO set to this box's root disk, e.g. the `/dev/disk/by-id/wwn-...`
          # or `/dev/disk/by-id/ata-...` link reported by `ls -l /dev/disk/by-id`
          # on the installer. apu's is `wwn-0x50026b77849de265`.
          disko.devices.disk.main.device = "/dev/disk/by-id/CHANGE-ME-ap-root-disk";
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
