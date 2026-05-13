{
  nixosModules.ssh = {
    services.sshd.enable = true;
    networking.firewall.allowedTCPPorts = [ 22 ];
    state = {
      files = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
    };
  };
}
