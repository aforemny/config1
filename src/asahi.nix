{ sources, ... }:
{
  _systems.defaultModules = [
    "${sources.nixos-apple-silicon}/apple-silicon-support"
    (
      { lib, ... }:
      {
        hardware.asahi.enable = lib.mkDefault false;
      }
    )
  ];
}
