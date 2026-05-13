{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.devShell = {
    package = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = pkgs.mkShell (lib.filterAttrs (name: _: name != "package") config.devShell);
    };
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
    shellHook = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };
  };
  config.devShell.packages = with pkgs; [
    npins
    cake-cli
  ];
}
