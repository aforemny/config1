{
  nixosModules.unfree =
    { config, lib, ... }:
    let
      cfg = config.unfree;
    in
    {
      options.unfree.packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
      config.nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) cfg.packages;
    };
}
