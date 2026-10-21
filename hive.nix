# Colmena hive -- plain Nix, no flakes. Run colmena from the devshell: its
# `colmena` wrapper passes `-f hive.nix` (src/colmena.nix), since colmena
# would otherwise prefer the flake.nix next to this file.
#
# Every cake system becomes a node built from the very same module list as
# `config.systems.<name>` (see src/options/systems.nix), so colmena and cake
# evaluate identical configurations.
#
# Secrets are agenix-rekey only and ship rekeyed in the closure, so there is
# nothing to copy besides it.
let
  cake = import ./. { };
  inherit (cake) lib sources;
  inherit (cake.config) systems;
in
{
  meta = {
    # Only a default: every node pins nixpkgs.hostPlatform itself (m1 is
    # aarch64-linux) and gets its own nixpkgs below.
    nixpkgs = import sources.nixpkgs { system = "x86_64-linux"; };
    nodeNixpkgs = lib.mapAttrs (_: system: import system.nixpkgs { system = "x86_64-linux"; }) systems;
  };
}
// lib.mapAttrs (name: system: {
  imports = system.modules;
  deployment = {
    targetHost = name;
    targetUser = "root";
    # x1e is the workstation: `colmena apply-local --sudo` deploys it.
    allowLocalDeployment = name == "x1e";
    # Build on the deploying machine, like cake deploy (m1 builds via
    # binfmt emulation, see src/emulated-systems.nix).
    buildOnTarget = false;
  };
}) systems
