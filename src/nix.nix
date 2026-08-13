{
  nixosModules.nix = { pkgs, ... }: {
    nix = {
      nixPath = [ "nixpkgs=${pkgs.path}" ];
      settings.experimental-features = [
        "flakes"
        "nix-command"
      ];
    };
  };
}
