{ sources, ... }:
{
  nixosModules.omp =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.tags.graphical (
      lib.mkMerge [
        {
          programs.sbox = {
            enable = true;
            bind."$HOME/.cache" = { };
            network = "isolated";
          };
        }
        {
          environment.systemPackages = with pkgs; [
            (builtins.getFlake "${
              builtins.unsafeDiscardStringContext sources."llm-agents.nix"
            }?narHash=${sources."llm-agents.nix".hash}").packages.${pkgs.stdenv.hostPlatform.system}.omp
          ];
        }
      ]
    );
  homeManagerModules.omp =
    { lib, osConfig, ... }: lib.mkIf osConfig.tags.graphical { state.directories = [ ".omp" ]; };
  _systems.defaultModules = [
    (builtins.getFlake "${builtins.unsafeDiscardStringContext sources.sbox}?narHash=${sources.sbox.hash}")
    .nixosModules.sbox
  ];
}
