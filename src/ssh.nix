{
  nixosModules.ssh = {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };
    networking.firewall.allowedTCPPorts = [ 22 ];
    state = {
      files = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
    };
    services.fail2ban.enable = true;
  };
  # known_hosts (and anything else ssh writes). Persist the directory even
  # though home-manager links keys into it: a persisted known_hosts *file*
  # breaks ssh-keygen -R, which replaces it by rename.
  homeManagerModules.ssh = {
    state.directories = [ ".ssh" ];
  };
}
