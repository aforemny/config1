{ sources, ... }:
{
  nixosModules.declarativeRuntime = {
    _module.args = { inherit ((builtins.getFlake (toString sources.declarative-runtime)).inputs) nix-tf-schema; };
  };
}
