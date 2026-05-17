{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
{
  options = {
    wrappers = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
    wrapperModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      readOnly = true;
      default =
        let
          wlib = import "${sources.wrappers}/lib" { inherit lib; };
        in
        (import sources.wrappers { inherit pkgs; }).wrapperModules
        // lib.mapAttrs (name: wlib.wrapModule) config.wrappers;
    };
  };
}
