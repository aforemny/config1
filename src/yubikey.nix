{
  nixosModules.yubikey = { lib, ... }: {
    programs.yubikey-manager.enable = true;
    programs.yubikey-touch-detector.enable = true;
    security.pam.u2f.enable = true;
    services.yubikey-agent.enable = true;
    services.fprintd.enable = lib.mkForce false; # TODO
  };
}
