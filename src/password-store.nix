{
  homeManagerModules.password-store =
    let
      stateDir = ".local/share/password-store";
    in
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        home.sessionVariables.PASSWORD_STORE_DIR = "$HOME/${stateDir}";
        programs.password-store = {
          enable = true;
          package = pkgs.pass.withExtensions (exts: with exts; [ pass-otp ]);
          settings.PASSWORD_STORE_DIR = "$HOME/${stateDir}";
        };
        state.directories = [ stateDir ];
      }
      {
        systemd.user.services."init-password-store".Service.ExecStart = "${
          pkgs.writeShellApplication {
            name = "init-password-store-script";
            runtimeInputs = with pkgs; [ gitMinimal ];
            text = ''
              set -x
              if [[ ! -d "$HOME"/${stateDir}/.git ]]; then
                cd "$HOME"/${lib.escapeShellArg stateDir}
                git init --initial-branch=main
                git remote add origin git@github.com:aforemny/password-store.git
                git config branch.main.remote origin
                git config branch.main.merge refs/heads/main
              fi
            '';
          }
        }/bin/init-password-store-script";
      }
    ];
}
