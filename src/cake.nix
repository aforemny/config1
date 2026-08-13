{
  config,
  lib,
  sources,
  ...
}:
{
  imports = [
    "${sources.cake}/cake-modules/cake-build/"
    "${sources.cake}/cake-modules/cake-cli/"
    "${sources.cake}/cake-modules/cake-deploy-ssh/"
    "${sources.cake}/cake-modules/cake-deploy/"
    "${sources.cake}/cake-modules/cake-eval/"
    "${sources.cake}/cake-modules/cake-install/"
    "${sources.cake}/cake-modules/cake-install/"
    "${sources.cake}/cake-modules/cake-repl/"
    "${sources.cake}/cake-modules/cake-run-vm/"
    "${sources.cake}/cake-modules/cake-show/"
  ];
  config = {
    overlays.cake-commands = self: super: {
      cake-commands = config._cake.cake-cli.top; # TODO
    };
    _cake.show = {
      nixosModules = lib.mapAttrsToList (
        name: _:
        lib.trim ''
          ${name}
        ''
      ) config.nixosModules;
      overlays = lib.mapAttrsToList (
        name: _:
        lib.trim ''
          ${name}
        ''
      ) config.overlays;
      platforms = lib.mapAttrsToList (
        name: _:
        lib.trim ''
          ${name}
        ''
      ) config.platforms;
      systems = lib.mapAttrsToList (
        name:
        { config, ... }:
        lib.trim ''
          ${name} (${config.nixpkgs.hostPlatform.system}, ${config.system.nixos.version})
        ''
      ) config.systems;
      tests = lib.mapAttrsToList (
        name: _:
        lib.trim ''
          ${name}
        ''
      ) config.tests;
    };
  };
}
