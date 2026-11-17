{ lib, sources, ... }:
{
  nixosModules.bootvine =
    { pkgs, ... }:
    {
      # TODO: services.bootvine (NixOS/nixpkgs#586741) is not in our nixpkgs
      # channel yet; drop this import, the package override and the
      # `nixpkgs-bootvine` pin once it is.
      imports = [ "${sources.nixpkgs-bootvine}/nixos/modules/services/system/bootvine.nix" ];

      services.bootvine = {
        enable = true;
        package = pkgs.callPackage "${sources.nixpkgs-bootvine}/pkgs/by-name/bo/bootvine/package.nix" {
          nixosTests = { };
        };
      };
    };

  # tower's boot asks for zdata's ZFS passphrase on the console, which
  # bootvine's live tree draws over.
  systems.tower.modules = [ { services.bootvine.enable = lib.mkForce false; } ];
}
