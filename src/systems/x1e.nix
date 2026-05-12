{
  systems.x1e.config = {
    boot.loader.grub.device = "nodev";
    fileSystems."/".fsType = "tmpfs";
    system.stateVersion = "26.05";
  };
}
