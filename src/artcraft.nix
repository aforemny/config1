{ sources, ... }:
{
  # The ArtCraft apps (Rust clones of commercial creative/office apps) on x1e.
  systems.x1e.modules = [
    (
      { pkgs, ... }:
      let
        # Build against artcraft-nix's own pinned nixpkgs (not ours) so the
        # outputs match what its CI pushes to Cachix and get substituted
        # instead of compiled.
        artcraft =
          import
            (import "${sources.artcraft-nix}/nix/tamal" {
              inherit (pkgs.stdenv.hostPlatform) system;
            }).nixpkgs
            {
              inherit (pkgs.stdenv.hostPlatform) system;
              overlays = [ (import "${sources.artcraft-nix}/overlay.nix") ];
            };
      in
      {
        environment.systemPackages = with artcraft; [
          cadcraft
          deckcraft
          designcraft
          effectcraft
          filmcraft
          gridcraft
          lightcraft
          pdfcraft
          photocraft
          soundcraft
          vectorcraft
          wordcraft
        ];
        nix.settings = {
          extra-substituters = [ "https://applicative-systems.cachix.org" ];
          extra-trusted-public-keys = [
            "applicative-systems.cachix.org-1:ND41hRBh0ST2abuI/oee3yWVf3n0FsAftyJJ/Tb7KDE="
          ];
        };
      }
    )
  ];
}
