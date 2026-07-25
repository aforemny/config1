{
  nixosModules.gnupg = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ gnupg ];
    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      pinentryPackage = pkgs.pinentry-qt;
    };
  };
  homeManagerModules.gnupg =
    { pkgs, lib, ... }:
    lib.mkMerge [
      {
        state.directories = [ ".gnupg" ];
      }
      {
        systemd.user.services."init-gnupg".Service.ExecStart = "${
          pkgs.writeShellApplication {
            name = "init-gnupg-script";
            runtimeInputs = with pkgs; [
              coreutils
              gawk
              gnupg
            ];
            inheritPath = false;
            text = ''
              set -x

              secret_file="$HOME"/.secrets/'Password Storage Key.asc'
              secret_name=$(basename "''${secret_file}" .asc)
              if ! gpg --list-secret-keys "$secret_name"; then
                gpg --batch --import "$secret_file"
                fpr=$(
                  gpg --import-options show-only --import --with-colons "$secret_file" |
                  awk -F: '/^fpr:/ { print $10; exit }'
                )
                echo "''${fpr}:6:" | gpg --import-ownertrust
              fi
            '';
          }
        }/bin/init-gnupg-script";
      }
    ];
}
