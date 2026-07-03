{ sources, ... }:
{
  nixosModules.kitty =
    { pkgs, ... }:
    let
      inherit (import sources.wrappers { inherit pkgs; }) wrapperModules;
    in
    {
      programs.starship = {
        enable = true;
        package = (wrapperModules.starship.apply { inherit pkgs; }).wrapper;
      };
    };
}
