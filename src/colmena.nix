{ config, pkgs, ... }:
{
  # Colmena deploys the hive in ./hive.nix. Unless told otherwise, colmena
  # searches upwards for flake.nix *or* hive.nix and picks the flake, whose
  # evaluation is pure and copies the whole repository to the store; point
  # it at the hive instead.
  devShell.packages = [
    (pkgs.writeShellScriptBin "colmena" ''
      for arg; do
        case $arg in
          -f | --config | --config=*) exec ${pkgs.colmena}/bin/colmena "$@" ;;
        esac
      done
      exec ${pkgs.colmena}/bin/colmena -f ${toString config._outPath}/hive.nix "$@"
    '')
  ];
}
