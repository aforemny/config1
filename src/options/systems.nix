{ config, lib, sources, ... }:
{
  options = {
    systems = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        let
          inherit (config._systems) defaultModules;
        in
        {
          config,
          options,
          name,
          ...
        }:
        {
          options = {
            config = lib.mkOption {
              type = lib.mkOptionType {
                name = "Toplevel NixOS config";
                merge =
                  loc: defs:
                  (import "${config.nixpkgs}/nixos/lib/eval-config.nix" {
                    modules = defaultModules ++ map (x: x.value) defs;
                  }).config;
              };
            };
            nixpkgs = lib.mkOption {
              type = lib.types.path;
              default = sources.nixpkgs;
            };
          };
        }
      )
    );
    default = { };
  };
  _systems.defaultModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [];
  };
};
}
