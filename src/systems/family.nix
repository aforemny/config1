{
  systems.family.modules = [
    (
      { lib, pkgs, ... }:
      {
        networking = {
          hostId = "30d27915";
          domain = "apostolforemny.de";
          networkmanager.enable = false;
        };
        tags.graphical = false;

        localAccounts = {
          aforemny.passwordFile = pkgs.asecret-lib.password "per-user/aforemny/apostolforemny.de/aforemny/password";
          shared.passwordFile = pkgs.asecret-lib.password "per-host/family/per-user/shared/password";
        };

        services.babeld.enable = lib.mkForce false;
        services.syncoid.enable = lib.mkForce false;
      }
    )
  ];
}
