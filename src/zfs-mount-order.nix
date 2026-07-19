{
  # disko's `zfs_fs` with a path `mountpoint` (e.g. tower's `zdata/local/media`
  # -> /srv/media, see platforms/tower.nix) sets a *native* ZFS mountpoint on the
  # dataset AND emits a `fileSystems` entry, so the dataset is mounted twice over:
  #   - `zfs-mount.service` runs `zfs mount -a`, which mounts every non-legacy
  #     dataset, and
  #   - the systemd `<mp>.mount` unit generated from `fileSystems`.
  # Nothing orders these two against each other, so at boot they race; whichever
  # loses hits `zfs_mount_at() failed: mountpoint or dataset is busy` and fails,
  # and a failed `.mount` unit trips `local-fs.target`. (initrd-mounted datasets
  # like /, /nix carry `x-initrd.mount` and are already mounted before stage-2's
  # `zfs mount -a`, so only stage-2 datasets such as /srv/media are affected.)
  #
  # Order the bulk `zfs mount -a` after the individual mount units: the `.mount`
  # unit wins, and `zfs mount -a` -- which skips already-mounted datasets -- turns
  # into a no-op for them. No dataset `mountpoint` property is changed, so nothing
  # is unmounted on a running host (a live `zfs set mountpoint=legacy` would tear
  # /srv/media out from under transmission/sonarr/radarr/jellyfin).
  nixosModules.zfs-mount-order =
    {
      config,
      lib,
      utils,
      ...
    }:
    let
      mountUnits = lib.pipe config.fileSystems [
        lib.attrValues
        (lib.filter (fs: fs.fsType == "zfs" && !(lib.elem "x-initrd.mount" fs.options)))
        (lib.map (fs: "${utils.escapeSystemdPath fs.mountPoint}.mount"))
      ];
    in
    lib.mkIf (mountUnits != [ ]) {
      systemd.services.zfs-mount.after = mountUnits;
    };
}
