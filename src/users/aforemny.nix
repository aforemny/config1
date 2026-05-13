{
  nixosModules."users/aforemny" =
    { config, ... }:
    {
      users = {
        users.aforemny = {
          uid = 1000;
          isNormalUser = true;
          group = "aforemny";
          password = "nixos"; # TODO
        };
        groups.aforemny.gid = config.users.users.aforemny.uid;
      };
    };
}
