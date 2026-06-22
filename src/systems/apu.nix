{ sources, ... }:
{
  systems.apu.modules = [
    {
      tags.graphical = false;
      networking = {
        networkmanager.enable = false;
        nftables.enable = true;
        hostId = "c05410b7";
        hostName = "apu";
      };
    }
  ];
}
