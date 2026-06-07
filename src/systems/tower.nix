{
  systems.tower.modules = [
    {
      networking = {
        hostId = "c32250b5";
        hostName = "tower";
      };
    }
    ( # TODO reconcile with wifi profile
      { lib, ... }:
      {
        networking.networkmanager.ensureProfiles.profiles.apu.ipv6 = {
          addr-gen-mode = lib.mkForce "eui64"; # TODO
          token = "::5143:4fdf:f468:2801";
        };
      }
    )
  ];
}
