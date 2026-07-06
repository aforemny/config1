{ sources, ... }:
{
  nixosModules.minecraft-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf (config.networking.hostName == "tower") {
      services.minecraft-servers = {
        enable = true;
        eula = true;
        openFirewall = true;
        servers.fabric = {
          enable = true;
          jvmOpts = "-Xms2G -Xmx4G";
          package = pkgs.fabricServers.fabric-26_1_2.override { jre_headless = pkgs.jdk25_headless; };
          serverProperties = {
            difficulty = 3;
            enforce-whitelist = true;
            level-type = "large_biomes";
            motd = "Hermitcraft Server Pack 2.0.1, large biomes";
            view-distance = 24;
            white-list = true;
          };
          whitelist = {
            Alsbach = "9e479252-1c7d-45dc-a6ba-5fb8b659af86";
            elbueblo = "3d0afb8e-3289-4b18-90c6-e113eb636e5b";
          };
          files = {
            "ops.json".value = [
              {
                name = "Alsbach";
                uuid = "9e479252-1c7d-45dc-a6ba-5fb8b659af86";
                level = 4;
              }
              {
                name = "elbueblo";
                uuid = "3d0afb8e-3289-4b18-90c6-e113eb636e5b";
                level = 4;
              }
            ];
          };
        };
      };
      networking.firewall.allowedUDPPorts = [ 24454 ];
      # Published as mc1.nomath.org by src/dns.nix.
      dns.dynamicAAAA = [ "mc1" ];
      nixpkgs.overlays = [ (import "${sources.nix-minecraft}/overlay.nix") ];
      unfree.packages = [ "minecraft-server" ];
      state.directories = [ config.services.minecraft-servers.dataDir ];
    };
  _systems.defaultModules = [ "${sources.nix-minecraft}/modules/minecraft-servers.nix" ];
}
