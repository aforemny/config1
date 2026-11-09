{
  # Hardkernel ODROID-M1S: Rockchip RK3566 (4x Cortex-A55), 8 GB RAM, on-board
  # eMMC, one M.2 NVMe slot, serial console on the UART header at 1500000 baud.
  # Both mainline U-Boot (odroid-m1s-rk3566_defconfig) and mainline Linux
  # (rockchip/rk3566-odroid-m1s.dtb) support the board.
  platforms.m1s =
    { config, pkgs, ... }:
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      hardware.facter = {
        enable = true;
        reportPath = ./m1s.json;
      };
      system.stateVersion = "26.11";

      # Mainline U-Boot, which boots the extlinux.conf below. The board has no
      # SPI flash, so U-Boot lives on the eMMC itself, at sector 64 (in front
      # of the first partition, see disko below):
      #
      #   cake build --expr config.systems.m1s.config.system.build.uboot
      #   dd if=result/u-boot-rockchip.bin of=/dev/mmcblk0 seek=64 conv=notrunc,fsync
      system.build.uboot = pkgs.buildUBoot {
        defconfig = "odroid-m1s-rk3566_defconfig";
        extraMeta.platforms = [ "aarch64-linux" ];
        env = {
          BL31 = "${pkgs.armTrustedFirmwareRK3568}/bl31.elf";
          ROCKCHIP_TPL = pkgs.rkbin.TPL_RK3566;
        };
        filesToInstall = [ "u-boot-rockchip.bin" ];
      };
      # DDR init blob (TPL) baked into U-Boot.
      unfree.packages = [ "rkbin" ];

      boot = {
        loader = {
          grub.enable = false;
          systemd-boot.enable = false;
          generic-extlinux-compatible.enable = true;
        };
        kernelParams = [ "console=ttyS2,1500000n8" ];
      };
      # Named in extlinux.conf (FDT rather than FDTDIR), so any U-Boot boots
      # it: one with an empty fdtfile, like the board's earlier eMMC install,
      # guesses rockchip-odroid-m1s.dtb, which does not exist.
      hardware.deviceTree.name = "rockchip/rk3566-odroid-m1s.dtb";
      hardware.enableRedistributableFirmware = true;
      fileSystems."/persist".neededForBoot = true;

      disko.devices = {
        disk.main = {
          type = "disk";
          # By id: the eMMC and an SD card may swap mmcblk numbers.
          device = "/dev/disk/by-id/mmc-MMC64G_0x6d669b79";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                # Keep the first 16 MiB free for U-Boot (written at sector 64).
                start = "16M";
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
          options.ashift = "12";
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
}
