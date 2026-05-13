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
    _cake.show.systems = lib.mapAttrsToList (
      name: { config, ... }: "${name} (${config.nixpkgs.system}, ${config.system.nixos.release})"
    ) config.systems;
  };
}
