{
  systems.x1e.modules = [
    {
      home-manager.users.aforemny.imports = [
        (
          { pkgs, ... }:
          {
            # Servers send their game to the client, so none is installed here.
            home.packages = [ pkgs.luanti-client ];
            state.directories = [ ".minetest" ];
          }
        )
      ];
    }
  ];
}
