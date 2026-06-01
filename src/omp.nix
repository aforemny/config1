{ sources, ... }:
{
  nixosModules.omp =
    { lib, pkgs, ... }:
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
          (builtins.getFlake "${builtins.unsafeDiscardStringContext sources."llm-agents.nix"}")
          .packages.${pkgs.stdenv.hostPlatform.system}.omp
        ];
      }
    ];
  homeManagerModules.omp = {
    state.directories = [ ".omp" ];
  };
  _systems.defaultModules = [
    (builtins.getFlake "${builtins.unsafeDiscardStringContext sources.sbox}").nixosModules.sbox
  ];
}
