{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
let
  towerConfig = config.systems.tower.config;
  # The operator's SSH public key (mirrors users/aforemny.nix).
  aforemnyKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN aforemny@x1e"; # TODO
  # Enable the SSH daemon and authorize the operator's key for root on every
  # installer ISO, so freshly booted media is reachable over the network.
  sshModule = {
    services.openssh.enable = true;
    users.users.root.openssh.authorizedKeys.keys = [ aforemnyKey ];
  };
  # Ship the installer with the nixos-facter hardware profiler and btop, and
  # enable the modern Nix CLI (nix-command) plus flakes, so the operator can
  # profile hardware and run flake-based installs from the live environment.
  toolingModule =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        btop
        nixos-facter
      ];
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  # On the auto-login console, present a live display of the machine's IP
  # addresses so a headless install can be reached over SSH. `watch` redraws
  # `ip address` every two seconds; press Ctrl-C to drop to a shell. Colour is
  # used on virtual consoles but omitted on serial consoles (e.g. ap), where the
  # ANSI escapes would otherwise render as literal text.
  consoleIpModule =
    { pkgs, ... }:
    {
      programs.bash.loginShellInit = ''
        if [[ $- == *i* && -z ''${SSH_CONNECTION:-} ]]; then
          case "$(tty)" in
            # Pseudo-terminal (SSH/tmux): leave a plain shell.
            /dev/pts/*) ;;
            # Virtual console: renders ANSI colour.
            /dev/tty[0-9]*)
              ${pkgs.procps}/bin/watch --color --interval 2 ${pkgs.iproute2}/bin/ip --brief --color address
              ;;
            # Serial console (e.g. ap) and other ttys: colour escapes show as
            # literal text, so display without colour.
            *)
              ${pkgs.procps}/bin/watch --interval 2 ${pkgs.iproute2}/bin/ip --brief address
              ;;
          esac
        fi
      '';
    };
  # A host's `apu` WiFi profile on the installer. The installer can't decrypt
  # the PSK, so it is not stored: join from the console with
  # `nmcli --ask connection up apu`.
  apuWifiModule = hostConfig: {
    networking.networkmanager.enable = true;
    networking.networkmanager.ensureProfiles.profiles.apu =
      let
        inherit (hostConfig.networking.networkmanager.ensureProfiles.profiles) apu;
      in
      apu
      // {
        wifi-security = removeAttrs apu.wifi-security [ "psk" ] // {
          psk-flags = 2; # NM_SETTING_SECRET_FLAG_NOT_SAVED: ask for it
        };
      };
  };
  # Reinstalling tower from the installer.
  towerInstallerModule = {
    imports = [
      # In case it is not on Ethernet.
      (apuWifiModule towerConfig)
    ];
    # Same hostId as tower, so zdata imports without `-f`.
    networking.hostId = towerConfig.networking.hostId;
  };
in
{
  options.isoImages = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };
  # TODO `systems.m1.config.system.build.isoImage`
  # Installer for reinstalling `tower`. Build with:
  #   cake build --expr config.isoImages.tower.config.system.build.isoImage
  # then `dd` it to a USB stick.
  config.isoImages.tower = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      #"${sources.disko}/module.nix"
      #"${sources.nixos-apple-silicon}/apple-silicon-support"
      "${sources.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      sshModule
      toolingModule
      consoleIpModule
      towerInstallerModule
      #config.platforms.m1
      (
        #  #{ lib, ... }:
        {
          #    disabledModules = [
          #      "${sources.nixos-images}/nix/latest-zfs-kernel.nix"
          #    ];
          #    #system.stateVersion = lib.mkForce lib.trivial.release;
          #hardware.asahi.peripheralFirmwareDirectory = ./platforms/m1;
        })
    ];
    #system = "aarch64-linux";
  };
  # Bootable installer image for `ap` (a second apu4d4). Build with:
  #   cake build --expr config.isoImages.ap.config.system.build.isoImage
  # then `dd` it to a USB stick and boot the apu over its serial console.
  config.isoImages.ap = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      "${sources.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      sshModule
      toolingModule
      consoleIpModule
      {
        # TODO facter does not set this
        boot.kernelParams = [
          "console=tty0"
          "console=ttyS0,115200n8"
        ];
        hardware.facter.enable = true;
        hardware.facter.reportPath = ./platforms/ap.json;
      }
    ];
  };
  # Bootable installer image for `m1`, built on nixos-apple-silicon's own
  # installer configuration (EFI boot via U-Boot, iwd, peripheral firmware
  # extracted from the ESP at boot). Build with:
  #   cake build --expr config.isoImages.m1.config.system.build.isoImage
  # then `dd` it to a USB stick and boot it from the U-Boot boot menu.
  config.isoImages.m1 = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      "${sources.nixos-apple-silicon}/apple-silicon-support"
      "${sources.nixos-apple-silicon}/iso-configuration/installer-configuration.nix"
      sshModule
      toolingModule
      consoleIpModule
      {
        # The upstream installer disables ZFS in case it does not build
        # against the Asahi kernel; m1's root pool needs it, and the pinned
        # ZFS builds against m1's kernel already.
        boot.supportedFilesystems.zfs = lib.mkForce true;
        # Same hostId as m1, so its pool imports without `-f`.
        networking.hostId = config.systems.m1.config.networking.hostId;
        # The upstream installer reads `nixpkgs.hostPlatform`.
        nixpkgs.hostPlatform = "aarch64-linux";
      }
    ];
  };
  # SD card installer for `m1s` (ODROID-M1S). Its eMMC is empty until the
  # install, so the board boots from SD. The image carries m1s's own U-Boot at
  # sector 64, like the eMMC will. Build with:
  #   cake build --expr config.isoImages.m1s.config.system.build.sdImage
  # then `zstdcat result/sd-image/*.img.zst | dd of=/dev/<sd card> bs=4M`
  # and watch the serial console (UART header, 1500000 baud).
  config.isoImages.m1s = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      "${sources.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64-installer.nix"
      sshModule
      toolingModule
      consoleIpModule
      (
        { lib, ... }:
        let
          uboot = config.systems.m1s.config.system.build.uboot;
        in
        {
          nixpkgs.hostPlatform = "aarch64-linux";
          # Same hostId as m1s, so its pool imports without `-f`.
          networking.hostId = config.systems.m1s.config.networking.hostId;
          hardware.deviceTree.name = config.systems.m1s.config.hardware.deviceTree.name;
          # The serial console last, so it becomes /dev/console; HDMI as tty1.
          boot.kernelParams = lib.mkAfter [
            "console=tty1"
            "console=ttyS2,1500000n8"
          ];
          sdImage = {
            # Room for U-Boot in front of the first partition, as on the eMMC
            # (see platforms/m1s.nix).
            firmwarePartitionOffset = 16;
            postBuildCommands = ''
              dd if=${uboot}/u-boot-rockchip.bin of=$img seek=64 conv=notrunc,fsync
            '';
          };
        }
      )
    ];
  };
  # USB installer for `pinebookpro`, the target for nixos-anywhere. An EFI
  # ISO, so any firmware with EFI boots it: Tow-Boot or the U-Boot from
  # platforms/pinebookpro.nix in the SPI flash. (An old Tow-Boot fails on
  # extlinux, as it places the initrd inside the kernel.) GRUB keeps the
  # firmware's device tree. Build with:
  #   cake build --expr config.isoImages.pinebookpro.config.system.build.isoImage
  # then `dd if=result/iso/*.iso of=/dev/<usb stick> bs=4M`.
  # The Pinebook Pro has no Ethernet: join WiFi from the console with
  # `nmcli --ask connection up apu` (or use a USB-C adapter), and put U-Boot
  # into the SPI flash with `flash-spi-uboot`. Then, from x1e, mint the host
  # key first, so agenix can decrypt on the first boot (rollback-rootfs: it
  # reads the key from /persist):
  #   mkdir -p host/persist/etc/ssh
  #   ssh-keygen -t ed25519 -N "" -f host/persist/etc/ssh/ssh_host_ed25519_key
  # add its .pub to src/host-keys.nix, `agenix rekey`, then
  #   cake build --expr config.systems.pinebookpro.config.system.build.diskoScript
  #   cake build --expr config.systems.pinebookpro.config.system.build.toplevel
  #   nixos-anywhere --store-paths <diskoScript> <toplevel> \
  #     --extra-files host \
  #     --disk-encryption-keys /tmp/secret.key <(read -rs p; printf %s "$p") \
  #     root@<ip>
  # and delete host/ afterwards.
  config.isoImages.pinebookpro = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      "${sources.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      sshModule
      toolingModule
      consoleIpModule
      (apuWifiModule config.systems.pinebookpro.config)
      (
        { lib, pkgs, ... }:
        let
          pinebookpro = config.systems.pinebookpro.config;
          uboot = pinebookpro.system.build.uboot;
        in
        {
          nixpkgs.hostPlatform = "aarch64-linux";
          # Same hostId as pinebookpro, so its pool imports without `-f`.
          networking.hostId = pinebookpro.networking.hostId;
          hardware.enableRedistributableFirmware = true;
          boot.kernelParams = lib.mkAfter pinebookpro.boot.kernelParams;
          environment.systemPackages = [
            (pkgs.writeShellApplication {
              name = "flash-spi-uboot";
              runtimeInputs = [ pkgs.mtdutils ];
              text = ''
                echo "Flashing $(cat /sys/class/mtd/mtd0/name) ($(cat /sys/class/mtd/mtd0/size) bytes)"
                flashcp --verbose ${uboot}/u-boot-rockchip-spi.bin /dev/mtd0
              '';
            })
          ];
        }
      )
    ];
  };
}
