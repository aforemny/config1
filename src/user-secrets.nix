{
  # Per-user secrets: every secrets/per-user/<user>/**.age (agenix-rekey,
  # master-key encrypted) is decrypted to /run/user-secrets/<user>/<path>,
  # owned by that user, and ~<user>/.secrets links there. Consumers read
  # ~/.secrets/<path> (neomutt, msmtp, vdirsyncer, gnupg, ~/.ssh).
  #
  # Secrets listed in `sealed` never appear in plaintext under ~/.secrets:
  # agenix leaves them root-only in /run/agenix, and user-secrets-seal
  # re-encrypts each one as a user-scoped systemd credential (bound to the
  # TPM where there is one) at ~/.secrets/<path>.cred. Read it with
  # `systemd-creds --user decrypt ~/.secrets/<path>.cred -`. Other modules
  # seal their own agenix secrets into ~/.secrets via `user-secrets.sealed`.
  nixosModules.user-secrets =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      users = [
        "aforemny"
        "root"
      ];
      sealed = {
        aforemny = [
          "a@foremny.me"
          "aforemny@nomath.org"
          "aforemny@posteo.de"
          "alexander.foremny@applicative.systems"
          "apostolforemny.de/aforemny/password"
          "Password Storage Key.asc"
        ];
      };
      isSealed = user: path: lib.elem path (sealed.${user} or [ ]);
      secretsDir = ../secrets/per-user;
      # Strings, not paths: these names (@, spaces) are not valid store paths,
      # so nothing here may be copied to the store.
      secretsOf =
        user:
        map (file: lib.removeSuffix ".age" (lib.removePrefix "${toString secretsDir}/${user}/" file)) (
          lib.filter (lib.hasSuffix ".age") (
            map toString (lib.filesystem.listFilesRecursive (secretsDir + "/${user}"))
          )
        );
      # agenix secret names end up in file names and scripts; keep them tame.
      secretName =
        user: path: "user-${user}-${lib.replaceStrings [ "/" " " "@" ] [ "-" "-" "-at-" ] path}";
    in
    {
      options.user-secrets.sealed = lib.mkOption {
        type = with lib.types; attrsOf (attrsOf str);
        default = { };
        example = {
          aforemny."example.org/password" = "example-password";
        };
        description = ''
          Per user, agenix secrets to seal at ~<user>/.secrets/<path>.cred,
          as `<path> = <age.secrets name>`. The agenix secret should stay
          root-only (the default owner).
        '';
      };
      config = {
        user-secrets.sealed = lib.mapAttrs (user: paths: lib.genAttrs paths (secretName user)) sealed;

        age.secrets = lib.listToAttrs (
          lib.concatMap (
            user:
            map (
              path:
              lib.nameValuePair (secretName user path) (
                {
                  rekeyFile = "${toString secretsDir}/${user}/${path}.age";
                }
                // lib.optionalAttrs (!isSealed user path) {
                  path = "/run/user-secrets/${user}/${path}";
                  owner = user;
                  inherit (config.users.users.${user}) group;
                  mode = "0400";
                }
              )
            ) (secretsOf user)
          ) users
        );
        # Re-sealed on every boot (/run is empty then) and whenever a sealed
        # secret changes, so the TPM/host key may change across boots.
        systemd.services.user-secrets-seal = {
          description = "Seal per-user secrets as user-scoped systemd credentials";
          wantedBy = [ "multi-user.target" ];
          wants = [ "tpm2.target" ];
          after = [ "tpm2.target" ];
          restartTriggers = lib.concatLists (
            lib.mapAttrsToList (
              _: secrets: lib.mapAttrsToList (_: name: config.age.secrets.${name}.file) secrets
            ) config.user-secrets.sealed
          );
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
          };
          path = [ config.systemd.package ];
          script = ''
            # host+tpm2 where there is a TPM; `auto` would refuse a host key on
            # a rollback rootfs, but we re-seal every boot anyway.
            if systemd-analyze has-tpm2 --quiet; then key=host+tpm2; else key=host; fi
          ''
          + lib.concatStrings (
            lib.concatLists (
              lib.mapAttrsToList (
                user:
                lib.mapAttrsToList (
                  path: name:
                  let
                    plain = "/run/user-secrets/${user}/${path}";
                    cred = "${plain}.cred";
                  in
                  # `decrypt` expects the credential's name to be its file name.
                  ''
                    install -d -m 0755 ${lib.escapeShellArg (dirOf cred)}
                    systemd-creds encrypt --with-key="$key" --uid=${user} \
                      --name=${lib.escapeShellArg (baseNameOf cred)} \
                      ${lib.escapeShellArg config.age.secrets.${name}.path} \
                      ${lib.escapeShellArg "${cred}.tmp"}
                    chown ${user}: ${lib.escapeShellArg "${cred}.tmp"}
                    mv ${lib.escapeShellArg "${cred}.tmp"} ${lib.escapeShellArg cred}
                    # Left over from before it was sealed; agenix doesn't remove
                    # old secret paths, and the name now resolves to its root-only copy.
                    if [ -L ${lib.escapeShellArg plain} ]; then rm ${lib.escapeShellArg plain}; fi
                  ''
                )
              ) config.user-secrets.sealed
            )
          );
        };
        systemd.tmpfiles.rules = map (
          user: "L+ ${config.users.users.${user}.home}/.secrets - - - - /run/user-secrets/${user}"
        ) users;
      };
    };
  homeManagerModules.user-secrets =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      linkTo = source: config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/${source}";
    in
    {
      config = {
        home.file = lib.mapAttrs (name: source: { source = linkTo source; }) {
          ".ssh/id_ed25519.pub" = ".secrets/id_ed25519.pub";
          ".ssh/id_ed25519" = ".secrets/id_ed25519";
        };
      };
    };
}
