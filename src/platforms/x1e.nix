{
  platforms.x1e =
    { lib, ... }:
    lib.mkMerge [
      {
        hardware.facter = {
          enable = true;
          reportPath = ./x1e.json;
        };
        nixpkgs.hostPlatform = "x86_64-linux";
        hardware.enableRedistributableFirmware = true;
        system.stateVersion = "21.05";
        environment.persistence."/persist" = { };
        fileSystems."/persist".neededForBoot = true;
      }
      {
        boot = {
          initrd.systemd.enable = true;
          initrd.availableKernelModules = [
            "nvme"
            "rtsx_pci_sdmmc"
            "sd_mod"
            "usb_storage"
            "xhci_pci"
          ];
          kernelModules = [ "kvm-intel" ];
          loader = {
            systemd-boot.enable = false;
            grub = {
              enable = true;
              efiInstallAsRemovable = true;
              efiSupport = true;
              zfsSupport = true;
              mirroredBoots = [
                {
                  path = "/boot0";
                  devices = [ "nodev" ];
                  efiSysMountPoint = "/boot0";
                }
                {
                  path = "/boot1";
                  devices = [ "nodev" ];
                  efiSysMountPoint = "/boot1";
                }
              ];
            };
          };
          zfs.requestEncryptionCredentials = [ "zroot" ];
        };
      }
      {
        # Discrete NVIDIA GPU driven in PRIME render-offload mode; the Intel iGPU
        # stays primary. `nvidia-offload <cmd>` runs a program on the dGPU.
        hardware.nvidia = {
          open = false;
          powerManagement = {
            enable = true;
            finegrained = true;
          };
          prime = {
            offload = {
              enable = true;
              enableOffloadCmd = true;
            };
            intelBusId = "PCI:0:2:0";
            nvidiaBusId = "PCI:1:0:0";
          };
        };
        services.xserver.videoDrivers = [ "nvidia" ];
        unfree.packages = [
          "nvidia-x11"
          "nvidia-settings"
          "nvidia-persistenced"
          "nvidia-kernel-modules"
        ];
      }
      (
        let
          disk = device: {
            inherit device;
            type = "disk";
            content = {
              type = "gpt";
              partitions = {
                ESP = {
                  size = "4G";
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    # nvme0n1 -> /boot0, nvme1n1 -> /boot1 (mirroredBoots)
                    mountpoint = null;
                    mountOptions = [ "umask=0077" ];
                  };
                };
                encryptedSwap = {
                  size = "32G";
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
        in
        {
          disko.devices = {
            disk = {
              nvme0n1 = lib.recursiveUpdate (disk "/dev/disk/by-id/nvme-eui.8ce38e0500481bb1") {
                content.partitions.ESP.content.mountpoint = "/boot0";
              };
              nvme1n1 = lib.recursiveUpdate (disk "/dev/disk/by-id/nvme-eui.8ce38e0500481f6a") {
                content.partitions.ESP.content.mountpoint = "/boot1";
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
                "safe" = {
                  type = "zfs_fs";
                  options.mountpoint = "none";
                  options."com.sun:auto-snapshot" = "true";
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
                "safe/persist" = {
                  type = "zfs_fs";
                  mountpoint = "/persist";
                };
              };
            };
          };
        }
      )
    ];
}
