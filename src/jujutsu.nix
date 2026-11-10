{ config, sources, ... }:
{
  nixosModules.jujutsu =
    { lib, pkgs, ... }:
    let
      inherit (import sources.wrappers { inherit pkgs; }) wrapperModules;
    in
    {
      environment.systemPackages = [
        (wrapperModules.jujutsu.apply (
          {
            inherit pkgs;
            settings.user = {
              name = "Alexander Foremny";
              email = "aforemny@posteo.de";
            };
          }
          # The aarch64 hosts build jujutsu themselves (cache.nixos.org lacks
          # it), m1s under qemu-user on x1e, where spawning a missing command
          # gives exit 127 rather than ENOENT and fails a bisect snapshot test.
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isAarch64 {
            package = lib.mkForce (pkgs.jujutsu.overrideAttrs { doCheck = false; });
          }
        )).wrapper
      ];
    };
  # Per-repo config (`jj config edit --repo`) and its metadata live outside
  # the repo, keyed by repo id.
  homeManagerModules.jujutsu = {
    state.directories = [ ".config/jj/repos" ];
  };
}
