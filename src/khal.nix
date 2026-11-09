{
  # khal, patched to create events on filesystems without hard links: it
  # saves a new event as a temporary file and hard-links it into place (to
  # never overwrite), which WebDAV mounts (rclone, davfs2) refuse. The patch
  # falls back to a rename after checking the target does not exist yet.
  overlays.khal = _: super: {
    khal = super.khal.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [ ./khal-link-fallback.patch ];
    });
  };

  # On x1e, khal works on the CalDAV servers directly instead of a vdirsyncer
  # copy: each server's calendar home is mounted over WebDAV with rclone (one
  # user service per server), and every calendar is a folder of .ics files
  # under it. Calendars get explicit khal entries: their folders are UUIDs,
  # and discovery would name them after those.
  systems.x1e.modules = [
    {
      # The family's `shared` Radicale account (src/systems/apostolforemny.nix), whose
      # password is only encrypted for apostolforemny otherwise. Also used by plann
      # (src/plann.nix).
      age.secrets.radicale-shared-password = {
        rekeyFile = ../secrets/per-host/apostolforemny/per-user/shared/password.age;
        owner = "aforemny";
      };

      home-manager.users.aforemny.imports = [
        (
          {
            config,
            lib,
            osConfig,
            pkgs,
            ...
          }:
          let
            mountDir = "${config.home.homeDirectory}/.calendar-dav";

            secret = path: "${config.home.homeDirectory}/.secrets/${path}";

            # <unit suffix> = server; `dir` is the folder under mountDir.
            servers = {
              # tower's Stalwart (src/stalwart.nix)
              nomath = {
                dir = "nomath.org";
                url = "https://cal.nomath.org/dav/cal/aforemny%40nomath.org/";
                user = "aforemny@nomath.org";
                passwordFile = secret "aforemny@nomath.org";
                calendars.nomath = "default";
              };
              # apostolforemny's Radicale (src/radicale.nix), via its direct vhost:
              # the Authelia-gated one is for browsers.
              apostolforemny = {
                dir = "apostolforemny.de";
                url = "https://calendar1.apostolforemny.de/aforemny/";
                user = "aforemny";
                passwordFile = secret "apostolforemny.de/aforemny/password";
                calendars = {
                  "time-2026" = "6FC18416-4B9B-4F13-9FF2-422A149D9DFD";
                  "Groceries" = "24B68254-7F18-4BA4-8128-32EAB8D62397";
                  "Kids Stuff" = "1A12AD0B-E959-4A6C-8C98-19A7EC54892A";
                  "reminders" = "5d887437-8458-eb9a-b96f-b73821eaa7a2";
                  "Nix UG" = "01AD744D-6D6B-4B24-9FBC-46E5CC5427DA";
                  "Hardware Store" = "30120FC5-66EA-4D51-9054-27BC0322EA2D";
                  "NixCon2026" = "DBC6EFC4-FCEC-4481-9AAB-204092D3D25F";
                };
              };
              # The same Radicale, the family's shared account. Its other
              # collection, "Shared Reminders", is a task list: khal shows
              # events only (plann has both).
              shared = {
                dir = "shared.apostolforemny.de";
                url = "https://calendar1.apostolforemny.de/shared/";
                user = "shared";
                passwordFile = osConfig.age.secrets.radicale-shared-password.path;
                calendars."shared reminders" = "8993B452-4CAE-4EE7-9F9F-170CE308781D";
              };
            };

            unitName = name: "calendar-dav-${name}";

            mountScript =
              name: server:
              pkgs.writeShellApplication {
                name = unitName name;
                runtimeInputs = [ pkgs.rclone ];
                text = ''
                  # The remote is defined in the environment only; no rclone.conf.
                  export RCLONE_CONFIG=/dev/null
                  export RCLONE_CONFIG_DAV_TYPE=webdav
                  export RCLONE_CONFIG_DAV_URL=${lib.escapeShellArg server.url}
                  export RCLONE_CONFIG_DAV_VENDOR=other
                  export RCLONE_CONFIG_DAV_USER=${lib.escapeShellArg server.user}
                  RCLONE_CONFIG_DAV_PASS="$(rclone obscure - < ${lib.escapeShellArg server.passwordFile})"
                  export RCLONE_CONFIG_DAV_PASS

                  # Short directory cache: changes made elsewhere show up within
                  # seconds. Writes go through a local cache and are uploaded
                  # when the file is closed.
                  exec rclone mount dav: ${lib.escapeShellArg "${mountDir}/${server.dir}"} \
                    --vfs-cache-mode writes \
                    --dir-cache-time 5s
                '';
              };
          in
          {
            home.packages = [ pkgs.khal ];

            systemd.user.services = lib.mapAttrs' (
              name: server:
              lib.nameValuePair (unitName name) {
                Unit.Description = "CalDAV calendars at ${server.url} mounted for khal";
                Install.WantedBy = [ "default.target" ];
                Service = {
                  Type = "notify"; # rclone reports when the mount is ready
                  ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountDir}/${server.dir}";
                  ExecStart = "${mountScript name server}/bin/${unitName name}";
                  ExecStop = "/run/wrappers/bin/fusermount3 -u ${mountDir}/${server.dir}";
                  # fusermount3 is a setuid wrapper, outside the store.
                  Environment = [ "PATH=/run/wrappers/bin" ];
                  Restart = "on-failure";
                  RestartSec = 10;
                };
              }
            ) servers;

            xdg.configFile."khal/config".text = ''
              [calendars]
              ${lib.concatStrings (
                lib.mapAttrsToList (
                  _: server:
                  lib.concatStrings (
                    lib.mapAttrsToList (name: folder: ''
                      [[${name}]]
                        path = ${mountDir}/${server.dir}/${folder}
                    '') server.calendars
                  )
                ) servers
              )}
              [default]
              default_calendar = reminders
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
