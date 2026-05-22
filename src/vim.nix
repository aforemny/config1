{
  homeManagerModules.vim =
    {
      config,
      lib,
      pkgs,
      sources,
      ...
    }:
    {
      programs.neovim = {
        enable = true;
        viAlias = true;
        vimAlias = true;
        vimdiffAlias = true;
        withNodeJs = true;
        withPython3 = true;
        withRuby = true;
        plugins = with pkgs.vimPlugins; [
          vim-nix
          zk-nvim
        ];
        extraConfig = ''
          set backspace=2

          set autoindent
          set expandtab
          set shiftwidth=2
          set tabstop=2

          set encoding=utf8

          set backup
          set backupcopy=yes

          set laststatus=2
          set number
        '';
      };
      home.sessionVariables.EDITOR = "vim";
    };
}
