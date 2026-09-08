{
  homeManagerModules.neomutt =
    {
      lib,
      osConfig,
      pkgs,
      ...
    }:
    lib.mkIf (osConfig.tags.graphical or false) (
      lib.mkMerge [
        {
          programs.neomutt = {
            enable = true;
            sidebar.enable = true;
            vimKeys = true;
            settings = {
              pipe_decode = "yes";
              rfc2047_parameters = "yes";
              sort_aux = "last-date";
              sort = "threads";
              wait_key = "no";
            };
            binds = [
              {
                map = [
                  "index"
                  "pager"
                ];
                key = "r";
                action = "group-reply";
              }
            ];
            macros = [
              {
                map = [
                  "index"
                  "pager"
                ];
                key = "B";
                action = "|${pkgs.urlscan}/bin/urlscan\\n";
              }
            ];
          };
          home.file = {
            ".mailcap".text = ''
              text/html; ${pkgs.lynx}/bin/lynx -stdin -dump -width ''${COLUMNS:-72}; copiousoutput
              text/calendar; ${pkgs.vcal}/bin/vcal -all -; copiousoutput
              application/pdf; ${pkgs.poppler-utils}/bin/pdftotext - -; copiousoutput
            '';
            ".urlview".text = ''
              COMMAND xdg-open %s
            '';
          };
        }
        {
          # Mailboxes are read over IMAP (no local sync), so neomutt talks to the
          # servers directly and sends through their SMTP. Passwords come from
          # ~/.secrets, the bindfs view of the asecret store (see user-secrets.nix).
          accounts.email.accounts = {
            "posteo.de" = {
              address = "aforemny@posteo.de";
              realName = "Alexander Foremny";
              primary = true;
              neomutt = {
                enable = true;
                mailboxType = "imap";
                extraMailboxes = [
                  "Drafts"
                  "Sent"
                  "Trash"
                ];
              };
              userName = "aforemny@posteo.de";
              passwordCommand = "cat ~/.secrets/aforemny@posteo.de";
              imap = {
                host = "posteo.de";
                port = 993;
              };
              smtp = {
                host = "posteo.de";
                port = 465;
              };
              signature = {
                showSignature = "append";
                text = ''
                  Alexander Foremny
                  Haltenhoffstr. 53, 30167 Hannover

                  Telefon: +49 176 613 370 68
                  E-Mail: aforemny@posteo.de

                  UStId-Nr.:  DE309468887
                '';
              };
            };
            "foremny.me" = {
              address = "a@foremny.me";
              realName = "Alexander Foremny";
              primary = false;
              neomutt = {
                enable = true;
                mailboxType = "imap";
                extraMailboxes = [
                  "Drafts"
                  "Sent"
                  "Trash"
                ];
              };
              userName = "a@foremny.me";
              passwordCommand = "cat ~/.secrets/a@foremny.me";
              imap = {
                host = "mx.foremny.me";
                port = 993;
              };
              smtp = {
                host = "mx.foremny.me";
                port = 465;
              };
              signature = {
                showSignature = "append";
                text = ''
                  Alexander Foremny
                '';
              };
            };
            "applicative.systems" = {
              address = "alexander.foremny@applicative.systems";
              realName = "Alexander Foremny";
              primary = false;
              neomutt = {
                enable = true;
                mailboxType = "imap";
                # Gmail's special folders live under the `[Gmail]/` namespace and
                # are named per the mailbox language, so they cannot be spelled
                # like the other accounts'. Verified against this account's IMAP
                # LIST: it is en-GB, hence `Bin` rather than `Trash`. Re-check
                # with an IMAP LIST if the mailbox language ever changes.
                extraMailboxes = [
                  "[Gmail]/Drafts"
                  "[Gmail]/Sent Mail"
                  "[Gmail]/All Mail"
                  "[Gmail]/Bin"
                ];
              };
              userName = "alexander.foremny@applicative.systems";
              # Google dropped password-only IMAP/SMTP for Workspace accounts in
              # 2025, so this must hold a 16-character app password (needs 2FA on
              # the account), not the login password.
              passwordCommand = "cat ~/.secrets/alexander.foremny@applicative.systems";
              imap = {
                host = "imap.gmail.com";
                port = 993;
              };
              smtp = {
                host = "smtp.gmail.com";
                port = 465;
              };
              folders = {
                inbox = "INBOX";
                drafts = "[Gmail]/Drafts";
                trash = "[Gmail]/Bin";
                # Gmail files every message sent through its SMTP into Sent Mail
                # on its own; letting neomutt upload a copy too (`record`) would
                # duplicate every sent message. null emits `unset record`.
                sent = null;
              };
            };
          };
        }
      ]
    );
}
