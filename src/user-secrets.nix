{
  nixosModules.user-secrets =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = {
        systemd.services."user-secrets@" = {
          description = "%i user secrets";
          partOf = [ "paths.target" ];
          serviceConfig = {
            Type = "forking";
            ExecStart = "${(pkgs.writeShellScript "user-secrets@-exec-start" ''
              set -eux
              home=$(${pkgs.getent}/bin/getent passwd $1 | cut -d: -f6)
              mkdir --parents $home/.secrets
              ${pkgs.bindfs}/bin/bindfs -o force-user=$1 -o force-group=$1 /var/src/secrets/per-user/$1 $home/.secrets
            '')} %i";
          };
        };

        systemd.targets.paths.wants = [
          "user-secrets@aforemny.service"
          "user-secrets@root.service"
        ];
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
        home.file =
          lib.mapAttrs
            (name: source: {
              source = linkTo source;
            })
            {
              ".ssh/id_ed25519.pub" = ".secrets/id_ed25519.pub";
              ".ssh/id_ed25519" = ".secrets/id_ed25519";
            };
      };
    };
}
