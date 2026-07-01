{
  nixosModules.comma =
    { pkgs, ... }:
    {
      # `comma` runs a program straight from nixpkgs without installing it:
      # typing `, <name>` (e.g. `, cowsay`) runs `nix-shell -p <name> --run <name>`.
      # It maps the typed command to a package via `nix-locate` (whose path is
      # baked into the comma binary at build time), so it relies on the nix-index
      # database -- populate it once per user with `nix-index`.
      environment.systemPackages = [ pkgs.comma ];

      # Provide `nix-index`/`nix-locate` on PATH so the database can be built and
      # queried. comma only needs that database, not the command-not-found shell
      # hook, so leave the shell integrations off.
      programs.nix-index = {
        enable = true;
        enableBashIntegration = false;
        enableZshIntegration = false;
        enableFishIntegration = false;
      };
    };
}
