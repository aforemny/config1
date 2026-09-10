{
  nixosModules.local-accounts =
    { lib, ... }:
    {
      options.localAccounts = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                username = lib.mkOption {
                  type = lib.types.str;
                  default = name;
                };
                passwordFile = lib.mkOption {
                  type = lib.types.str;
                };
              };
            }
          )
        );
        default = { };
      };
    };
}
