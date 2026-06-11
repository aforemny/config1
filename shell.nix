{
  pkgs ? import sources.nixpkgs { },
  sources ? import ./npins,
}:
let
  treefmt-nix = (import sources.treefmt-nix).mkWrapper pkgs (import ./treefmt.nix);
in
pkgs.mkShell { buildInputs = [ treefmt-nix ]; }
