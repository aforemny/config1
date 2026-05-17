{ config, lib, ... }:
{
  systems = lib.mapAttrs (name: _: {
    modules = [
      #{
      #  _file = "platforms.${name}";
      #  imports = [ config.platforms.${name} ];
      #}
      config.platforms.${name}
      {
        networking.hostName = name;
      }
    ];
  }) config.platforms;
}
