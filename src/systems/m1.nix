{
  systems.m1.modules = [
    {
      tags.workstation = true;
      networking = {
        hostId = "94118b97";
        hostName = "m1";
      };
      # 8 GB of RAM: with eight jobs, each on every core, building the Asahi
      # kernel, webkitgtk and jujutsu together ran out of memory, and the OOM
      # killer took rustc and the desktop shell.
      nix.settings.max-jobs = 2;
      # A single build may use every core: webkitgtk alone then compiles eight
      # ~1 GB C++ translation units at once, and with a Rust build alongside it
      # peaked at 5.4G of RAM and 7.4G of swap before the OOM killer took nix.
      nix.settings.cores = 4;
    }
  ];
}
