{ sources, ... }: {
  overlays.nm2nix = (
    self: super: {

      nm2nix = self.writers.writePython3Bin "nm2nix" { doCheck = false; } (
        builtins.readFile "${sources.nm2nix}/nm2nix.py"
      );
    }
  );
}
