{
  nixosModules.sanoid = {
    services.sanoid = {
      enable = true;
      datasets."zroot/safe" = {
        autoprune = true;
        autosnap = true;
        recursive = "zfs";
      };
    };
  };
}
