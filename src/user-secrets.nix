{
  # Per-user secrets: every secrets1/per-user/<user>/**.age (agenix-rekey,
  # master-key encrypted) is decrypted to /run/user-secrets/<user>/<path>,
  # owned by that user, and ~<user>/.secrets links there. Consumers read
  # ~/.secrets/<path> (neomutt, msmtp, vdirsyncer, gnupg, ~/.ssh).
  nixosModules.user-secrets =
    {
      config,
      lib,
      ...
    }:
    let
      users = [
        "aforemny"
        "root"
      ];
      secretsDir = ../secrets1/per-user;
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
      age.secrets = lib.listToAttrs (
        lib.concatMap (
          user:
          map (
            path:
            lib.nameValuePair (secretName user path) {
              rekeyFile = "${toString secretsDir}/${user}/${path}.age";
              path = "/run/user-secrets/${user}/${path}";
              owner = user;
              inherit (config.users.users.${user}) group;
              mode = "0400";
            }
          ) (secretsOf user)
        ) users
      );
      systemd.tmpfiles.rules = map (
        user: "L+ ${config.users.users.${user}.home}/.secrets - - - - /run/user-secrets/${user}"
      ) users;
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
