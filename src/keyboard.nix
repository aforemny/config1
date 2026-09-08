{
  nixosModules.keyboard = { lib, ... }: {
    services.xserver.xkb.layout = lib.mkDefault "us";
    services.xserver.xkb.variant = lib.mkDefault "altgr-intl";
    console.useXkbConfig = true;
  };
}
