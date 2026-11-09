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
    }
  ];
}
