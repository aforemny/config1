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
        # Every external display connector on this machine hangs off the discrete
        # NVIDIA GPU (card0: DP-1, DP-2, HDMI-A-1); the iGPU drives only the
        # internal eDP-1 panel. So a compositor always has to feed a CRTC that
        # lives on the other GPU than the one it renders on.
        #
        # Left alone, niri picks the boot_vga device (the iGPU, renderD128) as its
        # render node, which turns every external frame into a dGPU read of host
        # memory across PCIe -- 3840x2400x4B = 36.9 MB per frame, 2.2 GB/s at
        # 60 Hz. That does not fit, so the external monitor gets one frame every
        # two vblanks: a hard 30 Hz. Rendering on the dGPU instead makes the
        # external outputs local and leaves only eDP-1 crossing the bus, in the
        # dGPU->host write direction, which has ample headroom (measured: 60 Hz
        # on both outputs).
        programs.niri.config.settings.debug.render-drm-device = "/dev/dri/by-path/pci-0000:01:00.0-render";

        hardware.nvidia = {
          open = false;
          powerManagement = {
            enable = true;
            # No RTD3. The dGPU composites the session, so it never idles, and
            # NVreg_DynamicPowerManagement=0x02 actively hurts: compositor blits
            # do not register as GPU load, so it parks the GPU at P5 (memory 810
            # of 5001 MHz) and downtrains the link to PCIe Gen1/Gen2.
            finegrained = false;
          };
          # Only still here for X11 clients and the `nvidia-offload <cmd>`
          # wrapper; niri's render device is selected above.
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
