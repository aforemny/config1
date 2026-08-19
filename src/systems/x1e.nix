{
  systems.x1e.modules = [
    {
      networking.hostId = "05cfef68";
      i18n.supportedLocales = [
        "en_US.UTF-8/UTF-8"
        "de_DE.UTF-8/UTF-8"
      ];
    }
    {
      services.tailscale.enable = true;
      state.directories = [ "/var/lib/tailscale" ];
    }
    {
      hardware.bluetooth.enable = true;
    }
    {
      services.usbmuxd.enable = true;
    }
    {
      services.fwupd.enable = true;
    }
    (
      { pkgs, ... }:
      {
        services.printing = {
          enable = true;
          drivers = [
            pkgs.hplip
            pkgs.samsung-unified-linux-driver
            pkgs.splix
          ];
        };
        users.users.aforemny.extraGroups = [ "lp" ];
        unfree.packages = [ "samsung-unified-linux-driver" ];
      }
    )
    {
      # Steam, plus 32-bit graphics libraries it needs.
      programs.steam.enable = true;
      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;
      unfree.packages = [
        "steam"
        "steam-unwrapped"
        "steam-original"
        "steam-run"
      ];
    }
    (
      { pkgs, ... }:
      {
        # Android debugging.
        environment.systemPackages = [ pkgs.android-tools ];
        users.users.aforemny.extraGroups = [ "adbusers" ];
      }
    )
    (
      { pkgs, ... }:
      {
        powerManagement = {
          enable = true;
          powertop.enable = true;
          scsiLinkPolicy = "med_power_with_dipm";
        };
        services.thermald.enable = true;
        boot.kernelParams = [ "intel_pstate=disable" ];
        environment.systemPackages = with pkgs; [
          btop
          cpufrequtils
          pamixer
          powertop
          upower
        ];
        services.upower.enable = true;
      }
    )
    {
      services.kmonad = {
        enable = true;
        keyboards = {
          "x1e-internal" = {
            defcfg = {
              enable = true;
              fallthrough = true;
            };
            device = "/dev/input/by-path/platform-i8042-serio-0-event-kbd";
            config = ''
              (deflayer default caps esc lalt lmet)
              (defsrc esc caps lmet lalt)
            '';
          };
          "lenovo-trackpoint-ii" = {
            defcfg = {
              enable = true;
              fallthrough = true;
            };
            device = "/dev/input/by-id/usb-Lenovo_TrackPoint_Keyboard_II-event-kbd";
            config = ''
              (deflayer default caps esc lalt lmet)
              (defsrc esc caps lmet lalt)
            '';
          };
        };
      };
    }
    (
      { lib, pkgs, ... }:
      {
        # Outgoing mail via msmtp; the SMTP password comes from the asecret
        # store, read at send time by the (root) setuid sendmail wrapper.
        programs.msmtp = {
          enable = true;
          setSendmail = true;
          accounts.default = {
            auth = true;
            tls = true;
            host = "mx.foremny.me";
            port = "587";
            user = "a@foremny.me";
            from = "a@foremny.me";
            passwordeval = "echo $MSMTP_ACCOUNTS_DEFAULT_PASSWORD";
          };
        };
        services.mail.sendmailSetuidWrapper = {
          setuid = lib.mkForce true;
          source = lib.mkForce (
            pkgs.writers.writeDashBin "sendmail" ''
              set -efu
              MSMTP_ACCOUNTS_DEFAULT_PASSWORD=$(cat ${lib.escapeShellArg (pkgs.asecret-lib.password "per-user/aforemny/a@foremny.me")}); export MSMTP_ACCOUNTS_DEFAULT_PASSWORD
              exec ${pkgs.msmtp}/bin/sendmail "$@"
            ''
            + "/bin/sendmail"
          );
        };
      }
    )
    {
      # On-access antivirus for the user's Downloads. clamav uses
      # StateDirectory=clamav (systemd chowns the bind mount), so the bare
      # /var/lib/clamav string persists the signature database correctly.
      services.clamav = {
        daemon.enable = true;
        clamonacc.enable = true;
        daemon.settings = {
          OnAccessPrevention = true;
          OnAccessIncludePath = "/home/aforemny/Downloads";
        };
        updater.enable = true;
      };
      systemd.tmpfiles.rules = [ "d /home/aforemny/Downloads 0755 aforemny aforemny -" ];
      state.directories = [ "/var/lib/clamav" ];
    }
    {
      services.paperless = {
        enable = true;
        consumptionDirIsPublic = true;
        settings.PAPERLESS_OCR_LANGUAGE = "deu+eng";
        settings.PAPERLESS_OCR_ROTATE_PAGES = true;
      };
      # dataDir is created by the module via tmpfiles under user 'paperless'
      # (not StateDirectory=), so persist it with explicit ownership. Its redis
      # server uses StateDirectory= so a bare string is fine there.
      environment.persistence."/persist".directories = [
        {
          directory = "/var/lib/paperless";
          user = "paperless";
          group = "paperless";
          mode = "0700";
        }
      ];
      state.directories = [ "/var/lib/redis-paperless" ];
    }
    (
      { pkgs, ... }:
      {
        # Brother portable scanner (brscan5 + DSSeries + airscan).
        hardware.sane = {
          enable = true;
          brscan5.enable = true;
          dsseries.enable = true;
          extraBackends = [ pkgs.sane-airscan ];
        };
        unfree.packages = [
          "brscan5"
          "brscan5-etc-files"
          "libsane-dsseries"
        ];
        services.udev.extraRules = ''
          #
          #   udev rules sample for Brother MFP
          #         version 1.0.2-0
          #
          #   Copyright (C) 2012-2016 Brother. Industries, Ltd.
          #
          #   copy to /etc/udev/rules.d or /lib/udev/rules.d
          #

          ACTION!="add", GOTO="brother_mfp_end"

          SUBSYSTEM=="usb", GOTO="brother_mfp_udev_1"
          SUBSYSTEM!="usb_device", GOTO="brother_mfp_end"
          LABEL="brother_mfp_udev_1"


          ATTR{idVendor}=="04f9", GOTO="brother_mfp_udev_2"
          ATTRS{idVendor}=="04f9", GOTO="brother_mfp_udev_2"
          GOTO="brother_mfp_end"
          LABEL="brother_mfp_udev_2"

          ATTRS{bInterfaceClass}!="0ff", GOTO="brother_mfp_end"
          ATTRS{bInterfaceSubClass}!="0ff", GOTO="brother_mfp_end"
          ATTRS{bInterfaceProtocol}!="0ff", GOTO="brother_mfp_end"

          MODE="0666"
          GROUP="scanner"
          ENV{libsane_matched}="yes"
          SYMLINK+="scanner-%k"

          LABEL="brother_mfp_end"
        '';
      }
    )
    (
      { pkgs, ... }:
      {
        # Arion works with Docker, but for NixOS-based containers Podman is used.
        virtualisation.docker.enable = false;
        virtualisation.podman = {
          enable = true;
          dockerSocket.enable = true;
          defaultNetwork.settings.dns_enabled = true;
        };
        users.users.aforemny.extraGroups = [ "podman" ];
        environment.systemPackages = [
          pkgs.arion
          # docker CLI to talk to podman
          pkgs.docker-client
        ];
        state.directories = [ "/var/lib/containers" ];
      }
    )
    (
      { pkgs, ... }:
      {
        # 3D-printing slicers.
        environment.systemPackages = with pkgs; [
          snapmaker-luban
          orca-slicer
        ];
        nixpkgs.config.permittedInsecurePackages = [ "snapmaker-luban-4.15.0" ];
        unfree.packages = [ "snapmaker-luban" ];
        home-manager.users.aforemny.imports = [
          {
            state.directories = [
              ".config/snapmaker-luban"
              ".config/OrcaSlicer"
            ];
          }
        ];
      }
    )
    {
      home-manager.users.aforemny.imports = [
        (
          { pkgs, ... }:
          {
            home.packages = [ pkgs.hledger ];
            home.sessionVariables.LEDGER_FILE = "$HOME/src/finance/2021.journal";
            programs.bash.shellAliases.ledger = "hledger";
          }
        )
        (
          { config, ... }:
          {
            # CalDAV calendar (apostolforemny.de) synced with vdirsyncer; khal
            # reads it. The password comes from ~/.secrets (user-secrets bindfs
            # of the asecret store).
            accounts.calendar = {
              basePath = ".calendar";
              accounts."apostolforemny.de".remote = {
                type = "caldav";
                url = "apostolforemny.de";
                userName = "aforemny";
                vdirsyncer = {
                  enable = true;
                  auth = "basic";
                };
              };
            };
            programs.vdirsyncer.enable = true;
            home.file.".config/vdirsyncer/calendar.conf".text = ''
              [general]
              status_path = "${config.accounts.calendar.basePath}/apostolforemny.de"

              [pair default_calendar]
              a = "local_calendar"
              b = "remote_calendar"
              collections = ["from a", "from b"]

              [storage local_calendar]
              type = "filesystem"
              path = "${config.accounts.calendar.basePath}/apostolforemny.de"
              fileext = ".ics"

              [storage remote_calendar]
              type = "caldav"
              url = "https://calendar.apostolforemny.de/calendars/aforemny"
              username = "aforemny"
              password.fetch = ["command", "cat", "~/.secrets/apostolforemny.de/aforemny/password"]
            '';
            home.file.".config/khal/config".text = ''
              [calendars]
                [[default]]
                  path = ~/.calendar/apostolforemny.de/5d887437-8458-eb9a-b96f-b73821eaa7a2
                  color = dark blue
                  priority = 90
              [default]
              default_calendar = default
              highlight_event_days = true
              [locale]
              local_timezone = Europe/Berlin
              default_timezone = Europe/Berlin
              timeformat = %H:%M
              dateformat = %d.%m
              datetimeformat = %d.%m %H:%M
              longdatetimeformat = %d.%m.%Y %H:%M
            '';
          }
        )
      ];
    }
  ];
}
