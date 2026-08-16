{
  description = "aforemny/config — NixOS systems (cake framework) re-exposed as a flake";
  inputs = { };
  outputs =
    _:
    let
      probe = import ./. { system = "x86_64-linux"; };
      inherit (probe) lib;
      hostPlatforms = lib.mapAttrs (_: sys: sys.config.nixpkgs.hostPlatform.system) probe.config.systems;
      platforms = lib.unique (lib.attrValues hostPlatforms);
      cakeFor = system: import ./. { inherit system; };
      cakes = lib.genAttrs platforms cakeFor;
      nixosConfigurations = lib.mapAttrs (
        name: platform: (cakeFor platform).config.systems.${name}
      ) hostPlatforms;
    in
    {
      inherit nixosConfigurations;
      checks = lib.genAttrs platforms (
        platform:
        lib.listToAttrs (
          lib.concatLists (
            lib.mapAttrsToList (
              name: p:
              lib.optional (p == platform) (
                lib.nameValuePair name nixosConfigurations.${name}.config.system.build.toplevel
              )
            ) hostPlatforms
          )
        )
      );
      formatter = lib.genAttrs platforms (
        platform:
        (import cakes.${platform}.sources.treefmt-nix).mkWrapper cakes.${platform}.pkgs (
          import ./treefmt.nix
        )
      );
      devShells = lib.genAttrs platforms (platform: {
        default = cakes.${platform}.config.devShell.package;
      });
    };
}
