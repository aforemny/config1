{
  config,
  lib,
  sources,
  ...
}:
{
  options = {
    systems = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          let
            inherit (config._systems) defaultModules;
          in
          { config, ... }:
          {
            options = {
              config = lib.mkOption {
                type = lib.mkOptionType { name = "Toplevel NixOS config"; };
                readOnly = true;
                default =
                  (import "${config.nixpkgs}/nixos/lib/eval-config.nix" { inherit (config) modules; }).config;
              };
              options = lib.mkOption {
                type = lib.mkOptionType { name = "Toplevel NixOS config"; };
                readOnly = true;
                default =
                  (import "${config.nixpkgs}/nixos/lib/eval-config.nix" { inherit (config) modules; }).options;
              };
              modules = lib.mkOption { type = lib.types.listOf lib.types.deferredModule; };
              nixpkgs = lib.mkOption {
                type = lib.types.path;
                default = sources.nixpkgs;
              };
            };
            config.modules = defaultModules;
          }
        )
      );
      default = { };
    };
    _systems.defaultModules = lib.mkOption { type = lib.types.listOf lib.types.deferredModule; };
  };
  config._systems.defaultModules = lib.attrValues config.nixosModules;
}
