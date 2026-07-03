{
  config,
  lib,
  pkgs,
  sources,
  ...
}:
{
  options._agenix-rekey = {
    nixosConfigurations = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.unspecified;
      default = { };
    };
    masterIdentities = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
    };
    secretsDir = lib.mkOption {
      type = lib.types.path;
    };
    package = lib.mkOption {
      default =
        let
          allAppNames = [
            "edit-view"
            "generate"
            "rekey"
            "update-masterkeys"
          ];
          allApps = lib.genAttrs allAppNames (
            appName:
            import "${sources.agenix-rekey}/apps/${appName}.nix" {
              nodes = import "${sources.agenix-rekey}/nix/select-nodes.nix" {
                nixosConfigurations = config._agenix-rekey.nixosConfigurations;
                darwinConfigurations = { };
                homeConfigurations = { };
                collectHomeManagerConfigurations = true;
                inherit (pkgs) lib;
              };
              inherit pkgs;
              agePackage = pkgs: pkgs.rage;
              userFlake = {
                outPath = config._outPath;
              };
            }
          );
        in
        pkgs.callPackage "${sources.agenix-rekey}/nix/package.nix" {
          allApps = allApps;
        };
    };
  };
  config = {
    devShell.packages = [
      config._agenix-rekey.package
    ];
    nixosModules.agenix-rekey =
      let
        inherit (config) _agenix-rekey;
      in
      { config, ... }:
      {
        age.rekey = {
          inherit (_agenix-rekey) masterIdentities;
          storageMode = "local";
          localStorageDir = "${_agenix-rekey.secretsDir}/rekeyed/${config.networking.hostName}";
          generatedSecretsDir = "${_agenix-rekey.secretsDir}/generated";
        };
        # On rollback-rootfs hosts the SSH host keys are bind-mounted from
        # /persist (src/ssh.nix), but the agenix activation script runs before
        # that mount is ready on cold boot -- so no identity is found and every
        # secret fails to decrypt. Read the identities straight from /persist,
        # which is mounted early (neededForBoot). Scoped to hosts that actually
        # configure /persist; others keep agenix's /etc/ssh default.
        age.identityPaths = lib.mkIf (config.fileSystems ? "/persist") [
          "/persist/etc/ssh/ssh_host_ed25519_key"
          "/persist/etc/ssh/ssh_host_rsa_key"
        ];
        # TODO
        age.secrets.randomPassword = {
          generator.script = "passphrase";
        };
        # Generates an ed25519 SSH key (radicle uses these) and writes the
        # adjacent, comment-stripped public key next to the .age file, so the
        # pubkey can be committed and referenced at eval time.
        age.generators.ssh-ed25519-pub =
          {
            pkgs,
            lib,
            file,
            ...
          }:
          ''
            tmp=$(${pkgs.coreutils}/bin/mktemp -d)
            ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -C "" -f "$tmp/key" >/dev/null
            ${pkgs.coreutils}/bin/cut -d' ' -f1,2 "$tmp/key.pub" \
              > ${lib.escapeShellArg (lib.removeSuffix ".age" file + ".pub")}
            ${pkgs.coreutils}/bin/cat "$tmp/key"
            ${pkgs.coreutils}/bin/rm -rf "$tmp"
          '';
      };
    _agenix-rekey.nixosConfigurations = config.systems;
    _systems.defaultModules = [
      "${sources.agenix}/modules/age.nix"
      (import "${sources.agenix-rekey}/modules/agenix-rekey.nix" pkgs.path)
    ];
  };
}
