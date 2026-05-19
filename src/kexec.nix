{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
{
  options.kexec = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = { };
  };
  # TODO `systems.m1.config.system.build.kexecInstallerTarball`
  config.kexec.m1 = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    modules = [
      #"${sources.disko}/module.nix"
      "${sources.nixos-apple-silicon}/apple-silicon-support"
      "${sources.nixos-images}/nix/kexec-installer/module.nix"
      "${sources.nixos-images}/nix/noninteractive.nix"
      #config.platforms.m1
      (
        #{ lib, ... }:
        {
          disabledModules = [
            "${sources.nixos-images}/nix/latest-zfs-kernel.nix"
          ];
          #system.stateVersion = lib.mkForce lib.trivial.release;
          hardware.asahi.peripheralFirmwareDirectory = ./platforms/m1;
        })
    ];
    system = "aarch64-linux";
  };
}
