{ lib, pkgs, ... }:
{
  overlays.asecret = import "${/home/aforemny/s/asecret}/pkgs"; # TODO
  devShell.packages = with pkgs; [ asecret ];
}
