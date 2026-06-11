{
  nixosModules.tags = { lib, ... }: {
    options.tags.graphical = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };
}
