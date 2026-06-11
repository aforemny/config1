{
  nixosModules.syncoid =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      target = "root@tower:zdata/replicas/${config.networking.hostName}/zroot/safe";
      sshKey = pkgs.asecret-lib.sshKeyPair "per-user/root/syncoid_ed25519";
    in
    lib.mkMerge [
      {
        services.syncoid = {
          enable = true;
          sshKey = sshKey.privateKeyFile;
          user = "root"; # TODO
          group = "root"; # TODO
          commands = {
            "zroot/safe" = {
              inherit target;
              sendOptions = "Rw";
              recvOptions = "u";
              extraArgs = [ "--no-sync-snap" ];
            };
          };
        };
        systemd.services."syncoid-zroot-safe".serviceConfig.BindReadOnlyPaths = [ sshKey.privateKeyFile ];
        programs.ssh.knownHosts."tower".publicKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE5mTSll0rgxudcdaEwvOE4IFnA6rfcxROhpS6sTSK0u root@tower"; # TODO
        users.users.root.openssh.authorizedKeys.keys = [ sshKey.publicKey ]; # TODO
        environment.systemPackages = with pkgs; [
          lzop
          mbuffer
        ];
      }
    ];
}
