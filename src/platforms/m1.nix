{
  platforms.m1 =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        disko.devices = {
          disk.esp = {
            type = "disk";
            device = "/dev/disk/by-partuuid/eab932c7-700e-4dd2-bd74-65796f693a98";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          disk.linux = {
            type = "disk";
            device = "/dev/disk/by-partuuid/6e40af2b-9bec-4703-a5e2-c2c11f190275";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
          # The disk is shared with macOS, so disko must not partition it:
          # this partition is carved out of the end of the former (larger)
          # zroot partition by hand, before disko runs, with
          #
          #   sgdisk -d 5 \
          #     -n 5:15268870:57871477 -t 5:8300 -u 5:6e40af2b-9bec-4703-a5e2-c2c11f190275 \
          #     -n 7:57871478:59968629 -t 7:8200 -u 7:b999a059-bb4d-4512-80a6-278f0b90d7e7 \
          #     /dev/nvme0n1
          disk.swap = {
            type = "disk";
            device = "/dev/disk/by-partuuid/b999a059-bb4d-4512-80a6-278f0b90d7e7";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
          zpool.zroot = {
            type = "zpool";
            rootFsOptions = {
              acltype = "posixacl";
              atime = "off";
              compression = "zstd";
              mountpoint = "none";
              xattr = "sa";
              encryption = "aes-256-gcm";
              keyformat = "passphrase";
              keylocation = "prompt";
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
              "local/cache" = {
                type = "zfs_fs";
                mountpoint = "/var/cache";
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
      }
      {
        hardware = {
          asahi.enable = true;
          facter = {
            enable = true;
            reportPath = ./m1.json;
          };
        };
      }
      {
        boot.loader = {
          efi.canTouchEfiVariables = false;
          systemd-boot.enable = true;
        };
        hardware = {
          asahi = {
            extractPeripheralFirmware = true;
            peripheralFirmwareDirectory = ./m1;
          };
          asahi.setupAsahiSound = true;
          graphics.enable = true;
        };
        networking.networkmanager.wifi.backend = "iwd";
        services.libinput.enable = true;
        # Battery state for the desktop shell (Noctalia).
        services.upower.enable = true;
        system.stateVersion = "23.11";
        fileSystems."/persist".neededForBoot = true;
      }
      {
        services.kmonad = {
          enable = true;
          keyboards = {
            "m1-internal" = {
              defcfg = {
                enable = true;
                fallthrough = true;
              };
              device = "/dev/input/by-path/platform-23510c000.spi-cs-0-event-kbd";
              config = ''
                (deflayer default caps esc)
                (defsrc esc caps)
              '';
            };
          };
        };
        boot.extraModprobeConfig = ''
          options hid_apple fnmode=2
        '';
      }
    ];
}
