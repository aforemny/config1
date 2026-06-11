{
  homeManagerModules.minecraft = { pkgs, ... }: {
    home.packages = with pkgs; [ prismlauncher ];
    state.directories = [ ".local/share/PrismLauncher" ];
  };
}
