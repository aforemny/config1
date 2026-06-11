{ lib, ... }: {
  imports = lib.filter (name: lib.hasSuffix ".nix" name) (
    lib.filesystem.listFilesRecursive (lib.cleanSource ./src)
  );
}
