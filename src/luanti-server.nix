{ sources, ... }:
{
  systems.tower.modules = [
    (
      { config, pkgs, ... }:
      let
        fqdn = "luanti.nomath.org";
        port = 30000;
        # The engine ships no playable game. Its id is the directory name
        # without the "_game" suffix.
        gameId = "minetest";
        games = pkgs.linkFarm "luanti-games" {
          minetest_game = sources.minetest-game;
        };
      in
      {
        services.minetest-server = {
          enable = true;
          inherit gameId port;
          world = "/var/lib/minetest/.minetest/worlds/world";
          config = {
            server_name = "nomath.org";
            server_address = fqdn;
            disallow_empty_password = true;
          };
        };
        systemd.services.minetest-server.environment.LUANTI_GAME_PATH = "${games}";
        networking.firewall.allowedUDPPorts = [ port ];
        # Published as luanti.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "luanti" ];
        # The module's StateDirectory= chowns the bind-mount at start.
        state.directories = [ "/var/lib/minetest" ];
      }
    )
  ];
}
