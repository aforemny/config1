{
  nixosModules.zk =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    lib.mkIf config.tags.workstation {
      # `zk` is an fzf picker for the Markdown notes below $ZK_STATE_DIR; this is
      # not the zk-org tool of the same name.
      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "zk";
          runtimeInputs = with pkgs; [
            coreutils
            findutils
            fzf
            pandoc
          ];
          text = builtins.readFile ./zk.sh;
        })
      ];
      environment.variables.ZK_STATE_DIR = "$HOME/s/notes";
    };
}
