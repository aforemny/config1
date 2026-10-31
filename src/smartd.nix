{
  # SMART monitoring on tower. Its root SSD (zroot: /, /nix, /persist) is a
  # single disk with no redundancy, and shipped with SMART switched off; it
  # first showed SATA link errors on 2026-10-31. smartd watches every disk it
  # finds, keeps SMART (and offline data collection, attribute autosave) on,
  # runs a short self-test daily at 02:00 and a long one on Saturdays at 03:00,
  # and logs problems to the journal (plus a wall message to logged-in users).
  systems.tower.modules = [
    {
      services.smartd = {
        enable = true;
        defaults.autodetected = "-a -o on -S on -s (S/../.././02|L/../../6/03)";
      };
    }
  ];
}
