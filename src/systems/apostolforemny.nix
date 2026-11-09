{
  systems.apostolforemny.modules = [
    (
      { config, lib, ... }:
      {
        networking = {
          hostId = "30d27915";
          # FQDN apostolforemny.de, the name it is reached by.
          domain = "de";
          networkmanager.enable = false;
        };
        tags.graphical = false;
        localAccounts = {
          aforemny.passwordFile = config.age.secrets."user-aforemny-apostolforemny.de-aforemny-password".path;
          shared.passwordFile = config.age.secrets.family-shared-password.path;
        };
        age.secrets.family-shared-password.rekeyFile = ../../secrets/per-host/apostolforemny/per-user/shared/password.age;
        services.babeld.enable = lib.mkForce false;
        services.syncoid.enable = lib.mkForce false;
      }
    )
  ];
}
