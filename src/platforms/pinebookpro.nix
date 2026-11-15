{
  # Pine64 Pinebook Pro: Rockchip RK3399 (2x Cortex-A72 + 4x Cortex-A53),
  # 4 GB RAM, 64 GB eMMC, 16 MiB SPI flash, optional NVMe through the M.2
  # adapter, serial console on the headphone jack (UART switch on the board)
  # at 1500000 baud. Mainline U-Boot (pinebook-pro-rk3399_defconfig) and
  # mainline Linux (rockchip/rk3399-pinebook-pro.dtb) support it.
  platforms.pinebookpro =
    { lib, pkgs, ... }:
    {
      nixpkgs.hostPlatform = "aarch64-linux";
      # TODO Enable once the report exists:
      #   nixos-facter -o src/platforms/pinebookpro.json   (on the installer)
      #hardware.facter = {
      #  enable = true;
      #  reportPath = ./pinebookpro.json;
      #};
      system.stateVersion = "26.11";

      # Mainline U-Boot in the SPI flash, so booting does not depend on what
      # is on the eMMC (the boot ROM tries SPI before eMMC and SD). It boots
      # systemd-boot from the ESP through its EFI implementation. Flash it from
      # the installer (see src/iso-image.nix):
      #
      #   flash-spi-uboot
      #
      # u-boot-rockchip.bin is the image for sector 64 of an SD card or eMMC.
      system.build.uboot = pkgs.buildUBoot {
        defconfig = "pinebook-pro-rk3399_defconfig";
        extraMeta.platforms = [ "aarch64-linux" ];
        env.BL31 = "${pkgs.armTrustedFirmwareRK3399}/bl31.elf";
        filesToInstall = [
          "u-boot-rockchip.bin"
          "u-boot-rockchip-spi.bin"
        ];
      };
      # The RK3399's BL31 ships prebuilt PMU-M0 firmware.
      unfree.packages = [ "arm-trusted-firmware-rk3399" ];

      boot = {
        loader = {
          grub.enable = false;
          # U-Boot keeps no EFI variables: it finds systemd-boot at the
          # removable-media path, EFI/BOOT/BOOTAA64.EFI, which bootctl also
          # installs.
          efi.canTouchEfiVariables = false;
          systemd-boot.enable = true;
        };
        kernelParams = [
          # The panel last, so it becomes /dev/console.
          "console=ttyS2,1500000n8"
          "console=tty1"
          # 4 GB of RAM: by default the ARC may grow to half of it.
          "zfs.zfs_arc_max=536870912"
        ];
        # The passphrase prompt needs the eDP panel and the (USB) keyboard in
        # the initrd; the root pool needs eMMC or, with the adapter, NVMe.
        initrd.availableKernelModules = [
          # eMMC, SD
          "sdhci_of_arasan"
          "dw_mmc_rockchip"
          # NVMe
          "pcie_rockchip_host"
          "phy_rockchip_pcie"
          "nvme"
          # Panel
          "rockchipdrm"
          "panel_edp"
          "pwm_bl"
          # Keyboard and touchpad
          "phy_rockchip_inno_usb2"
          "ehci_platform"
          "ohci_platform"
          "usbhid"
          "hid_generic"
        ];
      };
      # Installed to the ESP; systemd-boot hands it to the kernel (U-Boot
      # would otherwise pass its own copy, which can lag behind the kernel's).
      hardware.deviceTree.name = "rockchip/rk3399-pinebook-pro.dtb";
      # WiFi/Bluetooth (AP6256, BCM43456) firmware and its board nvram.
      hardware.enableRedistributableFirmware = true;
      # brcmfmac can't do SAE (WPA3) with this chip: "Failed to select
      # authenticated key management type". apu runs WPA3 transition mode, so
      # WPA2-PSK with the same password works. The installer copies this
      # profile.
      networking.networkmanager.ensureProfiles.profiles.apu.wifi-security.key-mgmt =
        lib.mkForce "wpa-psk";
      hardware.graphics.enable = true;
      services.libinput.enable = true;
      fileSystems."/persist".neededForBoot = true;

      disko.devices = {
        disk.main = {
          type = "disk";
          # The eMMC: rk3399.dtsi's mmc aliases pin the numbering (SD card is
          # mmcblk1). With the NVMe adapter, the pool could go there instead.
          device = "/dev/mmcblk2";
          content = {
            type = "gpt";
            partitions = {
              ESP = {
                # Keep the first 16 MiB free, where a U-Boot for eMMC would go
                # (sector 64), even though it lives in the SPI flash.
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
            encryption = "aes-256-gcm";
            keyformat = "passphrase";
            keylocation = "prompt";
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
