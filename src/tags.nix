{
  nixosModules.tags =
    { lib, ... }:
    {
      options.tags.graphical = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      options.tags.workstation = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
}
