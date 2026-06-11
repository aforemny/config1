{ sources, ... }: {
  nixosModules.hyprspace =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ "${sources.hyprspace}/nixos" ];
      config.services.hyprspace = {
        enable = true;
        package = pkgs.hyprspace;
        privateKeyFile = pkgs.asecret-lib.password "hyprspace/${config.networking.hostName}";
        settings = {
          peers = lib.filter (peer: peer.name != config.networking.hostName) [
            {
              name = "tower";
              id = "12D3KooWL3emM1yHwWhzVFu1P3sXauPPzeCyPihSXTzEaef3jTtS";
            }
            {
              name = "x1e";
              id = "12D3KooWGYfy68ffXc4UAb5o4TES4TNjSLEA3GKraXKQnSyFb2J5";
            }
          ];
        };
      };
    };
}
