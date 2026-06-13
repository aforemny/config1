{
  nixosModules.rollback-root-fs =
    { config, lib, ... }:
    let
      cfg = config.rollback-root-fs;
    in
    {
      options.rollback-root-fs = {
        enable = lib.mkEnableOption "rollback-root-fs" // {
          default = true; # TODO
        };
        pool = lib.mkOption {
          default = "zroot";
        };
        snapshot = lib.mkOption {
          default = "${cfg.pool}/local/root@blank";
        };
      };
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          (lib.mkIf config.boot.initrd.enable {
            boot.initrd.systemd.services.rollback-rootfs = {
              wantedBy = [ "initrd.target" ];
              after = [ "zfs-import-${cfg.pool}.service" ];
              before = [ "sysroot.mount" ];
              path = [ config.boot.zfs.package ];
              unitConfig.DefaultDependencies = "no";
              serviceConfig.Type = "oneshot";
              script = "zfs rollback -r ${cfg.snapshot}";
            };
          })
          (lib.mkIf (!config.boot.initrd.enable) {
            boot.initrd.postResumeCommands = lib.mkAfter "zfs rollback -r ${cfg.snapshot}";
          })
        ]
      );
    };
}
