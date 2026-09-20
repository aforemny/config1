{
  nixosModules.nix =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        nix = {
          nixPath = [ "nixpkgs=${pkgs.path}" ];
          settings.experimental-features = [
            "flakes"
            "nix-command"
          ];
        };
      }
      {
        nix.settings = {
          auto-allocate-uids = true;
          experimental-features = [
            "auto-allocate-uids"
            "cgroups"
          ];
          extra-system-features = [ "uid-range" ];
          sandbox-paths = [ "/dev/net" ];
        };
      }
    ];
}
