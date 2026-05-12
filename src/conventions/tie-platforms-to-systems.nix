{ config, lib, ... }:
{
  systems = lib.mapAttrs (name: _: {
    modules = [
      config.platforms.${name}
      {
        networking.hostName = name;
      }
    ];
  }) config.platforms;
}
