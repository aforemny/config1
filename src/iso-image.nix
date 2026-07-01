{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
let
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
in
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
      sshModule
      toolingModule
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
      sshModule
      toolingModule
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
