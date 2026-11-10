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
        disko.devices.disk.ssd.device = "/dev/disk/by-id/ata-INTENSO_SSD_1642606001001109";
        hardware.facter = {
          enable = true;
          reportPath = ./tower.json;
        };
        # Pinned by MAC: the predictable name follows the PCI bus, so a new PCIe card
        # renames the NIC (enp4s0 -> enp5s0), which then matches neither facter's
        # networkd config nor NetworkManager (unmanaged-devices=enp*) and stays down.
        systemd.network.links."10-enp5s0" = {
          matchConfig.PermanentMACAddress = "bc:5f:f4:02:53:6e";
          linkConfig.Name = "enp5s0";
        };
        fileSystems."/persist".neededForBoot = true;
        system.stateVersion = "26.05";
        # Quadro T400 (TU117), for Jellyfin's transcoding (src/jellyfin.nix).
        # Headless: nothing here starts X, the option only selects the driver.
        services.xserver.videoDrivers = [ "nvidia" ];
        hardware.graphics.enable = true;
        hardware.nvidia = {
          open = true;
          nvidiaSettings = false;
          nvidiaPersistenced = true;
        };
        unfree.packages = [
          "nvidia-x11"
          "nvidia-persistenced"
        ];
      }
      {
        disko.devices = {
          disk.ssd = {
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
                  size = "16G";
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
          };
        };
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
              hdd0 = hdd 0 // {
                device = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR60JMX3";
              };
              hdd1 = hdd 1 // {
                device = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR61AGS6";
              };
              hdd2 = hdd 2 // {
                device = "/dev/disk/by-id/ata-ST16000NM000J-2TW103_ZR7148PL";
              };
              hdd3 = hdd 3 // {
                device = "/dev/disk/by-id/ata-ST16000NM001G-2KK103_ZL29JM8P";
              };
            };
            zpool = {
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
                  "local" = {
                    type = "zfs_fs";
                    options.mountpoint = "none";
                    options."com.sun:auto-snapshot" = "false";
                  };
                  "local/media" = {
                    type = "zfs_fs";
                    mountpoint = "/srv/media";
                  };
                  "local/webarchive" = {
                    type = "zfs_fs";
                    mountpoint = "/srv/webarchive";
                  };
                };
              };
            };
          };
        }
      )
    ];
}
