{ pkgs, sources, ... }:
{
  config.devShell.packages = [
    ((import sources.treefmt-nix).mkWrapper pkgs (import ../treefmt.nix))
  ];
}
