{ sources, ... }:
{
  _systems.defaultModules = [
    "${sources.nixos-apple-silicon}/apple-silicon-support"
  ];
}
