{
  platforms.tower =
    { lib, ... }:
    lib.mkMerge [
      {
        boot = {
          loader = {
            systemd-boot.enable = false;
            grub = {
              enable = true;
              efiInstallAsRemovable = true;
              efiSupport = true;
              zfsSupport = true;
            };
          };
          zfs.extraPools = [ "zdata" ];
          # do NOT request encryption credentials for filesystems `zdata/*`
          zfs.requestEncryptionCredentials = [
            "zdata"
            "zroot"
          ];
        };
        disko.devices.disk = {
          hdd0.device = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR60JMX3";
          hdd1.device = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR61AGS6";
          hdd2.device = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR7148PL";
          hdd3.device = "/dev/disk/by-id/ata-ST16000NM001G-2KK103_ZL29JM8P";
          msata.device = "/dev/disk/by-id/ata-SAMSUNG_MZMTD128HAFV-000L1_S15FNSAD327896";
        };
        hardware.facter = {
          enable = true;
          reportPath = ./tower.json;
        };
        fileSystems."/persist".neededForBoot = true;
        system.stateVersion = "26.05";
      }
      (
        let
          hdd = n: {
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                zdata = {
                  size = "100%";
                  content = {
                    type = "zfs";
                    pool = "zdata";
                  };
                };
              };
            };
          };
        in
        {
          disko.devices = {
            disk = {
              msata = {
                type = "disk";
                content = {
                  type = "gpt";
                  partitions = {
                    boot = {
                      size = "1M";
                      type = "EF02";
                      attributes = [ 0 ];
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
                    zroot = {
                      size = "100%";
                      content = {
                        type = "zfs";
                        pool = "zroot";
                      };
                    };
                  };
                };
              };
              hdd0 = hdd 0;
              hdd1 = hdd 1;
              hdd2 = hdd 2;
              hdd3 = hdd 3;
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
                  "safe" = {
                    type = "zfs_fs";
                    options.mountpoint = "none";
                    options."com.sun:auto-snapshot" = "true";
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
                  "safe/persist" = {
                    type = "zfs_fs";
                    mountpoint = "/persist";
                  };
                };
              };
              zdata = {
                type = "zpool";
                mode = "raidz2";
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
                options.ashift = "12";
                datasets = {
                  "replicas" = {
                    type = "zfs_fs";
                    options.mountpoint = "none";
                    options."com.sun:auto-snapshot" = "false";
                  };
                };
              };
            };
          };
        }
      )
    ];
}
