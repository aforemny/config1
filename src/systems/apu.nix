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
      # Always-on, passively-cooled router: pin the 1 GHz clock so bursty packet
      # softirq work never waits on a frequency ramp.
      powerManagement.cpuFreqGovernor = "performance";
    }
  ];
}
