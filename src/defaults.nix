{ config, ... }:
{
  nixosModules.defaults =
    { lib, ... }:
    {
      users.mutableUsers = false;
    };
}
