{
  config,
  lib,
  sources,
  ...
}:
{
  imports = [
    "${/home/aforemny/s/cake}/cake-modules/cake-build/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-cli/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-deploy-ssh/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-deploy/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-eval/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-install/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-repl/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-run-vm/" # TODO
    "${/home/aforemny/s/cake}/cake-modules/cake-show/" # TODO
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
          ${name} (${config.nixpkgs.system}, ${config.system.nixos.release})
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
