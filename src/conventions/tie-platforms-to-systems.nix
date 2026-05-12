{ config, lib, ... }: {
  systems = lib.mapAttrs (name: _: { config = {
      imports = [ config.platforms.${name} ];
      networking.hostName = name;
    };
  }) config.platforms;
}
