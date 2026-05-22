{
  homeManagerModules.bash = {
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
