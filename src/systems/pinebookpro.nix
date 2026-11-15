{
  # Pine64 Pinebook Pro: Rockchip RK3399 (2x Cortex-A72 + 4x Cortex-A53),
  # 4 GB RAM, eMMC, optional NVMe through the M.2 adapter. The hardware itself
  # (boot loader, kernel, disko, facter) belongs in src/platforms/pinebookpro.nix,
  # which also sets networking.hostName (src/conventions).
  systems.pinebookpro.modules = [
    {
      tags.workstation = true;
      networking.hostId = "20fbd3f4";
      # 4 GB of RAM: see m1, which runs out of memory with more jobs at 8 GB.
      nix.settings.max-jobs = 1;
    }
    {
      # Battery state for the desktop shell (Noctalia).
      services.upower.enable = true;
      # Pairings and link keys.
      hardware.bluetooth.enable = true;
      state.directories = [ "/var/lib/bluetooth" ];
    }
    {
      services.kmonad = {
        enable = true;
        keyboards."pinebookpro-internal" = {
          defcfg = {
            enable = true;
            fallthrough = true;
          };
          # The internal keyboard is a USB device (SH68F83 on the internal
          # hub); confirm the by-id name on the machine.
          device = "/dev/input/by-id/usb-HAILUCK_CO._LTD_USB_KEYBOARD-event-kbd";
          config = ''
            (deflayer default caps esc)
            (defsrc esc caps)
          '';
        };
      };
    }
  ];
}
