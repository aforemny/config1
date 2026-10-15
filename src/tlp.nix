{ ... }:
{
  systems.x1e.modules = [
    (
      { lib, ... }:
      {
        services.power-profiles-daemon.enable = lib.mkForce false;
        services.tlp = {
          enable = true;
          settings = {
            START_CHARGE_THRESH_BAT0 = 75;
            STOP_CHARGE_THRESH_BAT0 = 80;
            SATA_LINKPWR_ON_AC = "med_power_with_dipm";
            SATA_LINKPWR_ON_BAT = "med_power_with_dipm";
          };
        };
      }
    )
  ];
}
