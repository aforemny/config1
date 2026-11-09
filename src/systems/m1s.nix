{
  systems.m1s.modules = [
    {
      tags.graphical = false;
      networking = {
        hostId = "3d4d9769";
        # WiFi (a USB RTL8821CU) through the shared profiles (src/wifi.nix).
        # The on-board Ethernet stays with networkd.
        networkmanager.unmanaged = [ "interface-name:end*" ];
      };
    }
  ];
}
