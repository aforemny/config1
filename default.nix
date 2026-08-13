{
  lib ? import "${sources.nixpkgs}/lib",
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  specialArgs = {
    inherit sources system;
  };
  eval = lib.evalModules {
    modules = [
      {
        _asecret.PASSWORD_STORE_DIR = toString ./. + "/secrets";
        _agenix-rekey = {
          masterIdentities = [
            {
              identity = "~/.ssh/id_ed25519";
              pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBvRliydgYlyjKeMAEuVWWvmr82rZBXaA5ZM9U8r0pyN";
            }
          ];
          secretsDir = toString ./. + "/secrets1";
        };
        _outPath = ./.;
      }
    ]
    ++ lib.filter (lib.hasSuffix ".nix") (lib.filesystem.listFilesRecursive (toString ./. + "/src"));
    inherit specialArgs;
  };
in
eval
// specialArgs
// {
  inherit (eval._module.args) pkgs;
  inherit (eval._module.args.pkgs) lib;
}
