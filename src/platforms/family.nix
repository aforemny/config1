{
  platforms.family =
    { lib, modulesPath, ... }:
    {
      imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];
      config = lib.mkMerge [
        {
          hardware.facter = {
            enable = true;
            reportPath = ./family.json;
          };
          system.stateVersion = "25.11";
          fileSystems."/persist".neededForBoot = true;
          boot.loader = {
            systemd-boot.enable = false;
            grub.enable = true;
          };
          systemd.network.networks."40-enp1s0" = {
            matchConfig.Name = "enp1s0";
            address = [ "2a01:4f8:1c1b:e9e6::1/64" ];
            routes = [ { Gateway = "fe80::1"; } ];
            networkConfig = {
              DHCP = "ipv4";
              IPv6AcceptRA = false;
              IPv6PrivacyExtensions = "kernel";
            };
            linkConfig.RequiredForOnline = "routable";
          };
        }
        {
          disko.devices = {
            disk.main = {
              type = "disk";
              device = "/dev/sda";
              content = {
                type = "gpt";
                partitions = {
                  boot = {
                    size = "1M";
                    type = "EF02";
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
            zpool.zroot = {
              type = "zpool";
              rootFsOptions = {
                acltype = "posixacl";
                atime = "off";
                compression = "zstd";
                mountpoint = "none";
                xattr = "sa";
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
        }
      ];
    };
}
