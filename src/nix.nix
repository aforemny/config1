{
  nixosModules.nix =
    { lib, pkgs, ... }:
    lib.mkMerge [
      { nix.nixPath = [ "nixpkgs=${pkgs.path}" ]; }
      {
        # note: `builtins.getFlake` is used in config
        nix.settings.experimental-features = [
          "flakes"
          "nix-command"
        ];
      }
    ];
}
