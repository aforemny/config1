{
  # plann (https://plann.no), a command-line CalDAV client that talks to the
  # server on every command (no local sync), read-write. Not in nixpkgs; it
  # needs a newer caldav (>= 3.6) than nixpkgs carries, so it is built against
  # a private Python package set instead of overriding python3Packages for
  # everyone (calendar-cli & co. keep nixpkgs' caldav).
  #
  # The updated libraries skip their test suites: those need live CalDAV
  # servers (radicale, xandikos) and are nixpkgs' business once it catches up.
  overlays.plann = _: super: {
    plann =
      let
        python = super.python3.override {
          self = python;
          packageOverrides = pself: psuper: {
            calendaring-config = pself.buildPythonPackage rec {
              pname = "calendaring-config";
              version = "0.5.0";
              pyproject = true;
              src = pself.fetchPypi {
                pname = "calendaring_config";
                inherit version;
                hash = "sha256-7WiulqXZeQzfDqapM92v1hdSN1moo/0nPGOk88PcxBw=";
              };
              build-system = with pself; [
                hatchling
                hatch-vcs
              ];
              dependencies = [ pself.pyyaml ];
              pythonImportsCheck = [ "calendaring_config" ];
            };

            icalendar-searcher = psuper.icalendar-searcher.overridePythonAttrs rec {
              version = "1.3.0";
              src = pself.fetchPypi {
                pname = "icalendar_searcher";
                inherit version;
                hash = "sha256-nPm4gcVLWWv1hn4ib9cERgOhJNa7PPh5FxhU05AnR14=";
              };
              doCheck = false;
            };

            caldav = psuper.caldav.overridePythonAttrs (old: rec {
              version = "3.7.0";
              src = pself.fetchPypi {
                pname = "caldav";
                inherit version;
                hash = "sha256-4SFgDoWOYsNjG5RgFnoJloX3j0/9qYsaluRgx7JS+0U=";
              };
              dependencies = old.dependencies ++ [ pself.calendaring-config ];
              doCheck = false;
            });
          };
        };
      in
      python.pkgs.buildPythonApplication rec {
        pname = "plann";
        version = "1.3.0";
        pyproject = true;
        src = python.pkgs.fetchPypi {
          inherit pname version;
          hash = "sha256-X3lhM+WFBrvvdnHFX3fwz43nibUhIObfniPQGhIVKAs=";
        };
        build-system = with python.pkgs; [
          hatchling
          hatch-vcs
        ];
        dependencies = with python.pkgs; [
          caldav
          calendaring-config
          click
          dateparser
          icalendar
          icalendar-searcher
          python-dateutil
          pyyaml
          sortedcontainers
        ];
        pythonImportsCheck = [ "plann" ];
        meta = {
          description = "Command-line CalDAV client";
          homepage = "https://plann.no";
          license = super.lib.licenses.gpl3Plus;
          mainProgram = "plann";
        };
      };
  };

  # On x1e, against tower's Stalwart (src/stalwart.nix, with the app password
  # neomutt and aerc use) and apostolforemny's Radicale (src/radicale.nix); `default`
  # covers both, `--config-section` picks one. The URLs must be the calendar
  # homes: the caldav library cannot find the principal from
  # https://cal.nomath.org/, nor through Radicale's Authelia-gated vhost, so
  # Radicale is reached via its direct calendar1 vhost.
  systems.x1e.modules = [
    {
      home-manager.users.aforemny.imports = [
        (
          {
            config,
            osConfig,
            pkgs,
            ...
          }:
          let
            cat = path: [
              "cat" # run without a shell, so no `~`
              path
            ];
            secret = path: cat "${config.home.homeDirectory}/.secrets/${path}";
          in
          {
            home.packages = [ pkgs.plann ];
            xdg.configFile."caldav/calendar.yaml".text = builtins.toJSON {
              nomath = {
                url = "https://cal.nomath.org/dav/cal/aforemny%40nomath.org/";
                username = "aforemny@nomath.org";
                password_command = secret "aforemny@nomath.org";
              };
              apostolforemny = {
                url = "https://calendar1.apostolforemny.de/aforemny/";
                username = "aforemny";
                password_command = secret "apostolforemny.de/aforemny/password";
              };
              # The family's shared account; its secret comes from src/khal.nix.
              shared = {
                url = "https://calendar1.apostolforemny.de/shared/";
                username = "shared";
                password_command = cat osConfig.age.secrets.radicale-shared-password.path;
              };
              default.contains = [
                "nomath"
                "apostolforemny"
                "shared"
              ];
            };
          }
        )
      ];
    }
  ];
}
