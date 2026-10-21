{
  nixosModules."users/aforemny" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkMerge [
      {
        # agenix decrypts before the `users` activation step, so this is in
        # place when the password is set (also root's, below).
        age.secrets.aforemny-hashed-password.rekeyFile = ../../secrets1/users/aforemny/hashed-password.age;
        users = {
          users.aforemny = {
            uid = 1000;
            isNormalUser = true;
            group = "aforemny";
            hashedPasswordFile = config.age.secrets.aforemny-hashed-password.path;
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN aforemny@x1e" # TODO
            ];
            extraGroups = [
              "audio"
              "networkmanager"
              "users"
              "video"
              "wheel"
            ];
          };
          groups.aforemny.gid = config.users.users.aforemny.uid;
        };
      }
      {
        users = {
          users.root = {
            inherit (config.users.users.aforemny) hashedPasswordFile;
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN aforemny@x1e" # TODO
            ];
          };
        };
      }
    ];
}
