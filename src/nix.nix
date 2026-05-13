{
  nixosModules.nix =
    { pkgs, ... }:
    {
      nix.nixPath = [
        "nixpkgs=${pkgs.path}"
      ];
    };
}
