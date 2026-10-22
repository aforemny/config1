{
  homeManagerModules.bash = {
    # A bind-mounted file is fine: with histappend (home-manager's default)
    # bash appends to it in place instead of replacing it.
    state.files = [ ".bash_history" ];
    programs.bash = {
      enable = true;
      shellAliases = {
        ag = "ag --ignore \\*~";
        feh = "feh --scale-down";
        grep = "grep --color=auto";
        ls = "ls --color=auto --hide=lost+found --hide=\\*~ --group-directories-first --classify";
        sudo = "sudo ";
      };
      initExtra = "set -o vi";
    };
  };
}
