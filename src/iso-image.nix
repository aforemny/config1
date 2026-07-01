{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
{
  options.isoImages = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };
  # TODO `systems.m1.config.system.build.isoImage`
  config.isoImages.tower = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      #"${sources.disko}/module.nix"
      #"${sources.nixos-apple-silicon}/apple-silicon-support"
      "${sources.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
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
  config.isoImages.m1 = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      #"${sources.disko}/module.nix"
      "${sources.nixos-apple-silicon}/apple-silicon-support"
      "${sources.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
      #config.platforms.m1
      (
        #  #{ lib, ... }:
        {
          #    disabledModules = [
          #      "${sources.nixos-images}/nix/latest-zfs-kernel.nix"
          #    ];
          #    #system.stateVersion = lib.mkForce lib.trivial.release;
          hardware.asahi.peripheralFirmwareDirectory = ./platforms/m1;
        })
    ];
    system = "aarch64-linux";
  };
}
