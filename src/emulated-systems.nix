{
  nixosModules.emulated-systems =
    { lib, pkgs, ... }:
    lib.mkIf (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
    };
}
