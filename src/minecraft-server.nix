{ sources, ... }:
{
  nixosModules.minecraft-server =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Hermitcraft Server Pack, pinned by ./minecraft-server/update-modpack.sh.
      modpackLock = lib.importJSON ./minecraft-server/modpack.json;
      modpack = pkgs.fetchModrinthModpack {
        pname = "hermitcraft-server";
        inherit (modpackLock) version url packHash;
      };
    in
    lib.mkIf (config.networking.hostName == "tower") {
      services.minecraft-servers = {
        enable = true;
        eula = true;
        openFirewall = true;
        servers.fabric = {
          enable = true;
          jvmOpts = "-Xms2G -Xmx4G";
          # Minecraft and Fabric loader versions follow the modpack.
          package =
            pkgs.fabricServers."fabric-${lib.replaceStrings [ "." ] [ "_" ] modpackLock.minecraft}".override
              {
                loaderVersion = modpackLock.fabricLoader;
                jre_headless = pkgs.jdk25_headless;
              };
          symlinks = {
            mods = "${modpack}/mods";
            datapacks = "${modpack}/datapacks";
          };
          serverProperties = {
            difficulty = 3;
            enforce-whitelist = true;
            level-type = "large_biomes";
            motd = "Hermitcraft Server Pack ${modpackLock.version}, large biomes";
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
