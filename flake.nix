{
  description = "aforemny/config — NixOS systems (evalModules tree in default.nix) re-exposed as a flake";
  inputs = { };
  outputs =
    _:
    let
      probe = import ./. { system = "x86_64-linux"; };
      inherit (probe) lib;
      hostPlatforms = lib.mapAttrs (_: sys: sys.config.nixpkgs.hostPlatform.system) probe.config.systems;
      platforms = lib.unique (lib.attrValues hostPlatforms);
      rootFor = system: import ./. { inherit system; };
      roots = lib.genAttrs platforms rootFor;
      nixosConfigurations = lib.mapAttrs (
        name: platform: (rootFor platform).config.systems.${name}
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
        (import roots.${platform}.sources.treefmt-nix).mkWrapper roots.${platform}.pkgs (
          import ./treefmt.nix
        )
      );
      devShells = lib.genAttrs platforms (platform: {
        default = roots.${platform}.config.devShell.package;
      });
    };
}
