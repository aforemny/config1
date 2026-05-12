{ config, ... }:
{
  nixosModules.defaults = {
    virtualisation = {
      vmVariant = {
        services.getty.autologinUser = "root";
        virtualisation = {
          cores = 12;
          memorySize = 16 * 1024;
          resolution = {
            x = 3840;
            y = 2160;
          };
          diskImage = null;
        };
      };
    };
  };
  _systems.defaultModules = [ config.nixosModules.defaults ];
}
