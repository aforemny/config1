{
  homeManagerModules.zk =
    { osConfig, lib, ... }:
    lib.mkIf (osConfig.tags.workstation or false) {
      programs.zk = {
        enable = true;
        settings.notebook.dir = "~/s/notes";
      };
      home.activation.zkNotebook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run mkdir -p "$HOME/s/notes/.zk"
      '';
    };
}
