{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config._asecret;
in
{
  options._asecret.PASSWORD_STORE_DIR = lib.mkOption {
    type = lib.types.path;
  };
  config = {
    nixosModules.asecret = "${/home/aforemny/s/asecret}/modules"; # TODO
    overlays = {
      asecret = import "${/home/aforemny/s/asecret}/pkgs"; # TODO
      nix-plugins =
        self: super:
        let
          major = "2";
          minor = "30";
        in
        {
          nix = super.nixVersions."nix_${major}_${minor}"; # TODO
          nix-plugins = (
            super.nix-plugins.override {
              nixComponents = super.nixVersions."nixComponents_${major}_${minor}";
            }
          );
        };
    };
    devShell = {
      packages = with pkgs; [
        asecret
        nix
      ];
      shellHook = ''
        export PASSWORD_STORE_DIR=${cfg.PASSWORD_STORE_DIR}
        export NIX_CONFIG='
          plugin-files = ${pkgs.nix-plugins}/lib/nix/plugins
          extra-builtins-file = ${/home/aforemny/s/asecret}/extra-builtins.nix
        '
      '';
    };
  };
}
