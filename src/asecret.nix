{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
let
  cfg = config._asecret;
in
{
  options._asecret.PASSWORD_STORE_DIR = lib.mkOption { type = lib.types.path; };
  config = {
    nixosModules.asecret =
      { lib, options, ... }:
      {
        imports = [
          "${sources.asecret}/modules"
        ];
        config = lib.mkIf (options ? "state") { state.directories = [ "/var/src/secrets" ]; };
      };
    overlays = {
      asecret = lib.composeManyExtensions [
        (import "${sources.asecret}/pkgs" # TODO
        )
        (
          self: super:
          let
            major = "2";
            minor = "31";
          in
          {
            nix = super.nixVersions."nix_${major}_${minor}"; # TODO
            nix-plugins = (
              super.nix-plugins.override { nixComponents = super.nixVersions."nixComponents_${major}_${minor}"; }
            );
          }
        )
        (self: super: { nixos-anywhere = super.nixos-anywhere.override { nix = super.nix; }; })
      ];
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
          extra-builtins-file = ${sources.asecret}/extra-builtins.nix
        '
      '';
    };
    _cake.cake-cli.cake-deploy.postCopyClosure = ''
      ASECRET_OUT=$target1:/var/src/secrets asecret export
    '';
    _cake.cake-cli.cake-install.preInstall = ''
      extra_files=$(
        out=$tmp/asecret
        mkdir -p "$out"/persist/var/src/secrets
        ASECRET_OUT="$out"/persist/var/src/secrets asecret export
        echo "$out"
      )
      nixos_anywhere_args+=(--extra-files "$extra_files")
    '';
  };
}
