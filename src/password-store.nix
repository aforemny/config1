{
  homeManagerModules.password-store =
    let
      stateDir = ".local/share/password-store";
    in
    { lib, ... }:
    lib.mkMerge [
      {
        programs.password-store = {
          enable = true;
          settings.PASSWORD_STORE_DIR = "$HOME/${stateDir}";
        };
        state.directories = [ stateDir ];
      }
    ];
}
