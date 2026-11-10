{
  config,
  lib,
  sources,
  ...
}:
{
  nixosModules.persistence =
    { config, ... }:
    let
      cfg = config.environment.persistence."/persist";

      # Where impermanence bind-mounts /persist (`where` of its mount units).
      persistMounts = map (m: m.where) (
        lib.filter (m: lib.hasPrefix "/persist/" m.what) config.systemd.mounts
      );

      under = parent: path: path == parent || lib.hasPrefix "${parent}/" path;
    in
    {
      # A live `switch` starts a newly persisted directory's mount, but the
      # service using it isn't restarted (its unit text is unchanged; the
      # implicit RequiresMountsFor= of StateDirectory= etc. is computed by
      # systemd) -- it keeps writing into the now-shadowed ephemeral dir.
      # Spelling out RequiresMountsFor= for every persist mount overlapping a
      # service's paths changes its unit whenever that set changes, so
      # switch-to-configuration restarts it, ordered after the mount.
      # Anything written to the ephemeral dir before the switch is shadowed
      # (as it would be lost on reboot).  Services whose data dir is not in
      # StateDirectory=/WorkingDirectory=/ReadWritePaths= etc. (e.g. created
      # via tmpfiles) need an explicit `unitConfig.RequiresMountsFor`.
      options.systemd.services = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            let
              sc = config.serviceConfig;
              toList =
                v:
                if v == null then
                  [ ]
                else if lib.isList v then
                  lib.concatMap toList v
                else if lib.isString v then
                  lib.filter (s: s != "") (lib.splitString " " v)
                else
                  [ ];
              get = name: toList (sc.${name} or null);
              dynamic = lib.elem (sc.DynamicUser or false) [
                true
                "yes"
                "true"
                "on"
                "1"
              ];
              # systemd's `source:symlink` form; only the source is a real dir.
              relative =
                name: base:
                map (d: "${base}${lib.optionalString dynamic "/private"}/${lib.head (lib.splitString ":" d)}") (
                  get name
                );
              absolute =
                name:
                lib.filter (lib.hasPrefix "/") (map (lib.removePrefix "-") (map (lib.removePrefix "+") (get name)));
              paths =
                relative "StateDirectory" "/var/lib"
                ++ relative "CacheDirectory" "/var/cache"
                ++ relative "LogsDirectory" "/var/log"
                ++ absolute "WorkingDirectory"
                ++ absolute "ReadWritePaths";
              mounts = lib.filter (m: lib.any (p: under m p || under p m) paths) persistMounts;
            in
            {
              config = lib.mkIf (cfg.enable && mounts != [ ]) {
                unitConfig.RequiresMountsFor = mounts;
              };
            }
          )
        );
      };

      config = lib.mkMerge [
        {
          environment.persistence."/persist" = {
            # Two independent modules may legitimately persist the same path
            # (e.g. radicle and keycloak both need /var/lib/acme); impermanence
            # rejects exact duplicates, so collapse them here.
            directories = lib.mkIf cfg.enable (lib.unique config.state.directories);
            files = lib.mkIf cfg.enable (lib.unique config.state.files);
          };
        }
        {
          environment.persistence."/persist" = {
            directories = lib.mkIf cfg.enable [
              "/var/lib/nixos"
              # Without this the journal dies with the rootfs on every boot, so
              # nothing that made a machine fail to come up can be read after
              # rebooting into a generation that does -- exactly when the log is
              # needed.  journald caps it at 10% of the pool either way.
              "/var/log"
              # Persistent= timers (fstrim, zpool-trim, fwupd-refresh, ...)
              # catch up on a missed run only if their stamp survives; without
              # it a machine that is off at the scheduled time never runs them.
              "/var/lib/systemd/timers"
            ];
            # The rollback root wipes /etc on every boot; unless machine-id is
            # persisted it is regenerated each boot, which reshuffles everything
            # derived from it -- notably systemd-networkd's `persistent` MAC (so
            # bridge MACs churn) and the DHCP DUID -- so DHCP leases and IPs move
            # on every reboot.
            files = lib.mkIf cfg.enable [ "/etc/machine-id" ];
          };
        }
      ];
    };
  _systems.defaultModules = [ "${sources.impermanence}/nixos.nix" ];
  homeManagerModules.persistence =
    { osConfig, config, ... }:
    let
      cfg = osConfig.environment.persistence."/persist";
    in
    {
      home.persistence."/persist" = {
        directories = lib.mkIf cfg.enable config.state.directories;
        files = lib.mkIf cfg.enable config.state.files;
      };
    };
}
