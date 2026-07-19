{
  # Random-encrypted swap (`swapDevices.*.randomEncryption`, here produced by
  # disko's `type = "swap"; randomEncryption = true`) opens a *plain* dm-crypt
  # mapper (DM_UUID=CRYPT-PLAIN-*) and runs `mkswap` on it inside the generated
  # `mkswap-<dev>.service`. The kernel emits no "change" uevent for the mapper
  # after `mkswap` writes the swap signature, so udev's database keeps
  # ID_FS_TYPE empty and tags the device SYSTEMD_READY=0. Its
  # `dev-mapper-<dev>.device` unit therefore never activates, and the
  # fstab-generated `<dev>.swap` unit -- which `Requires=` that device -- blocks
  # for the full 90s device timeout before `swap.target` fails.
  #
  # `sysinit.target` is ordered `After=swap.target`, so that 90s stall delays the
  # entire boot: systemd-networkd (and thus the `lan` bridge) start only once the
  # swap job has timed out, by which point `sys-subsystem-net-devices-lan.device`
  # has itself hit its 90s timeout -- so on apu hostapd and dnsmasq, which depend
  # on that device, come up as "dependency failed" after a cold power-cycle.
  #
  # Force a udev re-probe of the mapper the moment `mkswap` finishes: ID_FS_TYPE
  # is recorded as `swap`, the device is marked ready, its `.device` unit
  # activates immediately, swap comes up, and the boot no longer stalls.
  nixosModules.encrypted-swap =
    { config, lib, ... }:
    {
      systemd.services = lib.listToAttrs (
        lib.map (sw: {
          name = "mkswap-${sw.deviceName}";
          value.serviceConfig.ExecStartPost = "${config.systemd.package}/bin/udevadm trigger --settle --action=change ${sw.realDevice}";
        }) (lib.filter (sw: sw.randomEncryption.enable) config.swapDevices)
      );
    };
}
