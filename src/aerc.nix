{
  # aerc on x1e, alongside neomutt, on the same IMAP/SMTP accounts
  # (src/neomutt.nix); passwords come from their passwordCommand.
  systems.x1e.modules = [
    {
      home-manager.users.aforemny.imports = [
        (
          { lib, pkgs, ... }:
          {
            programs.aerc = {
              enable = true;
              extraConfig = {
                # accounts.conf is a read-only nix-store file, never 0600; it
                # holds no credentials, only the cred-cmds.
                general.unsafe-accounts-conf = true;
                ui = {
                  threading-enabled = true;
                  sort = "-r date";
                };
                filters = {
                  "text/plain" = "colorize";
                  "text/calendar" = "${pkgs.vcal}/bin/vcal -all -";
                  "text/html" = "${pkgs.lynx}/bin/lynx -stdin -dump -width $AERC_COLUMNS";
                  "message/delivery-status" = "colorize";
                  "message/rfc822" = "colorize";
                  "application/pdf" = "${pkgs.poppler-utils}/bin/pdftotext - -";
                  ".headers" = "colorize";
                };
              };
            };
            accounts.email.accounts =
              lib.genAttrs
                [
                  "posteo.de"
                  "foremny.me"
                  "applicative.systems"
                  "nomath.org"
                ]
                (_: {
                  aerc.enable = true;
                });
          }
        )
      ];
    }
  ];
}
