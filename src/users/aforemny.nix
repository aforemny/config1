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
        users = {
          users.aforemny = {
            uid = 1000;
            isNormalUser = true;
            group = "aforemny";
            hashedPasswordFile = pkgs.asecret-lib.hashedPassword "users/aforemny/hashed-password";
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN aforemny@x1e" # TODO
            ];
            extraGroups = [ "wheel" ];
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
