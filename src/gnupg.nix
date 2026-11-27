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
              systemd
            ];
            inheritPath = false;
            text = ''
              set -x

              # Sealed user secret (src/user-secrets.nix).
              secret_file="$HOME"/.secrets/'Password Storage Key.asc.cred'
              secret_name=$(basename "''${secret_file}" .asc.cred)
              secret() { systemd-creds --user decrypt "$secret_file" -; }
              if ! gpg --list-secret-keys "$secret_name"; then
                secret | gpg --batch --import
                fpr=$(
                  secret | gpg --import-options show-only --import --with-colons |
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
