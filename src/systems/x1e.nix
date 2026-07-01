{
  config,
  options,
  pkgs,
  ...
}:
{
  # system x1e has not been ported yet and is only a placeholder here.
  # its configuration and deployment is not accessible from this repository.
  systems.x1e.modules = [
    {
      boot.loader.grub.device = "nodev";
      fileSystems."/".fsType = "tmpfs";
      system.stateVersion = "26.05";
    }
  ];
  tests.x1e = pkgs.testers.runNixOSTest {
    name = "x1e";
    nodes.x1e.imports = config.systems.x1e.modules;
    testScript = ''
      x1e.succeed("which niri");
    '';
  };
}
