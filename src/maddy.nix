{ lib, ... }:
let
  fqdn = "mail.nomath.org";
  domain = "nomath.org";
  selector = "default";
  publicIPv4 = "91.99.63.134";
  dkimRecord = lib.fileContents ../secrets1/generated/maddy-dkim-key.pub;
  # TXT allows at most 255 bytes, RSA-20248 is ~410
  dkimTxt =
    let
      size = 200;
      count = (builtins.stringLength dkimRecord + size - 1) / size;
    in
    lib.concatMapStringsSep " " (i: ''"${builtins.substring (i * size) size dkimRecord}"'') (
      lib.range 0 (count - 1)
    );
in
{
  # Two things still have to be done by hand, once, at cutover:
  #
  #   1. Point the PTR of 91.99.63.134 at mail.nomath.org (Hetzner Cloud
  #      console, project holding server "homelab", or
  #      POST /v1/servers/62440927/actions/change_dns_ptr). It is not a unit
  #      like set-hetzner-dns because that project's API token is not in the
  #      asecret store -- only the token for the project holding the DNS zone
  #      is. Until then the address keeps Hetzner's default
  #      static.134.63.99.91.clients.your-server.de, which is forward-confirmed
  #      and therefore already passes the check tower failed; matching the HELO
  #      name is the remaining improvement.
  #   2. Delete the stale `mail` AAAA RRSet (it still points at tower). The
  #      reconciler below only creates and updates what it declares, so it
  #      cannot express a deletion:
  #      DELETE /v1/zones/nomath.org/rrsets/mail/AAAA
  #      Do it right after the A record exists, otherwise receivers keep
  #      connecting to tower, which no longer answers on 25.
  systems.family.modules = [
    (
      { config, ... }:
      {
        age.secrets.maddy-dkim-key = {
          generator.script = "dkim-rsa";
          owner = "maddy";
        };
        age.secrets.maddy-admin-password = {
          generator.script = "alnum";
          owner = "maddy";
        };
        age.secrets.maddy-postmaster-password = {
          generator.script = "alnum";
          owner = "maddy";
        };

        services.maddy = {
          enable = true;
          hostname = fqdn;
          primaryDomain = domain;
          localDomains = [ domain ];
          openFirewall = true; # 25 (SMTP), 143 (IMAP+STARTTLS), 587 (submission)

          tls = {
            loader = "file";
            certificates = [
              {
                certPath = "/var/lib/acme/${fqdn}/fullchain.pem";
                keyPath = "/var/lib/acme/${fqdn}/key.pem";
              }
            ];
          };

          ensureAccounts = [
            "admin@${domain}"
            "postmaster@${domain}"
          ];
          ensureCredentials = {
            "admin@${domain}".passwordFile = config.age.secrets.maddy-admin-password.path;
            "postmaster@${domain}".passwordFile = config.age.secrets.maddy-postmaster-password.path;
          };

          config = ''
            auth.pass_table local_authdb {
              table sql_table {
                driver sqlite3
                dsn credentials.db
                table_name passwords
              }
            }

            storage.imapsql local_mailboxes {
              driver sqlite3
              dsn imapsql.db
            }

            table.chain local_rewrites {
              optional_step regexp "(.+)\+(.+)@(.+)" "$1@$3"
              optional_step static {
                entry postmaster postmaster@$(primary_domain)
              }
              optional_step file /etc/maddy/aliases
            }

            msgpipeline local_routing {
              destination postmaster $(local_domains) {
                modify {
                  replace_rcpt &local_rewrites
                }
                deliver_to &local_mailboxes
              }
              default_destination {
                reject 550 5.1.1 "User doesn't exist"
              }
            }

            smtp tcp://0.0.0.0:25 {
              limits {
                all rate 20 1s
                all concurrency 10
              }
              dmarc yes
              check {
                require_mx_record
                dkim
                spf
              }
              source $(local_domains) {
                reject 501 5.1.8 "Use Submission for outgoing SMTP"
              }
              default_source {
                destination postmaster $(local_domains) {
                  deliver_to &local_routing
                }
                default_destination {
                  reject 550 5.1.1 "User doesn't exist"
                }
              }
            }

            submission tcp://0.0.0.0:587 {
              limits {
                all rate 50 1s
              }
              auth &local_authdb
              source $(local_domains) {
                check {
                  authorize_sender {
                    prepare_email &local_rewrites
                    user_to_email identity
                  }
                }
                destination postmaster $(local_domains) {
                  deliver_to &local_routing
                }
                default_destination {
                  modify {
                    # Signs with the committed key instead of one maddy mints on
                    # first start, which is what makes the TXT record below
                    # publishable from the repo.
                    dkim {
                      domains $(primary_domain)
                      selector ${selector}
                      key_path ${config.age.secrets.maddy-dkim-key.path}
                    }
                  }
                  deliver_to &remote_queue
                }
              }
              default_source {
                reject 501 5.1.8 "Non-local sender domain"
              }
            }

            target.remote outbound_delivery {
              limits {
                destination rate 20 1s
                destination concurrency 10
              }
              mx_auth {
                dane
                mtasts {
                  cache fs
                  fs_dir mtasts_cache/
                }
                local_policy {
                  min_tls_level encrypted
                  min_mx_level none
                }
              }
            }

            target.queue remote_queue {
              target &outbound_delivery
              autogenerated_msg_domain $(primary_domain)
              bounce {
                destination postmaster $(local_domains) {
                  deliver_to &local_routing
                }
                default_destination {
                  reject 550 5.0.0 "Refusing to send DSNs to non-local addresses"
                }
              }
            }

            imap tcp://0.0.0.0:143 {
              auth &local_authdb
              storage &local_mailboxes
            }
          '';
        };

        # family already terminates TLS for its own vhosts; mail only needs the
        # challenge location, and maddy reads the cert straight off disk.
        services.nginx = {
          enable = true;
          virtualHosts.${fqdn}.locations."/.well-known/acme-challenge".root = "/var/lib/acme/acme-challenge";
        };
        security.acme.certs.${fqdn} = {
          webroot = "/var/lib/acme/acme-challenge";
          group = "maddy";
          reloadServices = [ "maddy.service" ];
        };
        systemd.services."acme-${fqdn}" = {
          after = [ "nginx.service" ];
          wants = [ "nginx.service" ];
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        state.directories = [
          "/var/lib/maddy"
          "/var/lib/acme"
        ];
      }
    )
  ];

  # The mail records live in the nomath.org zone, whose tofu state belongs to
  # the reconciler on tower (src/dns.nix) -- so they are declared from tower
  # even though the service runs on family. Enabling a second reconciler on
  # family instead would hand these RRSets to a fresh state file while tower's
  # state still lists them, and tower's next apply would delete them.
  systems.tower.modules = [
    {
      services.hetzner-dns.runtime = {
        zone_rrsets.mail_a = {
          zone = domain;
          name = "mail";
          type = "A";
          records = [ { value = publicIPv4; } ];
        };
        zone_rrsets.mx = {
          zone = domain;
          name = "@";
          type = "MX";
          records = [ { value = "10 ${fqdn}."; } ];
        };
        zone_rrsets.dkim = {
          zone = domain;
          name = "${selector}._domainkey";
          type = "TXT";
          records = [ { value = dkimTxt; } ];
        };
        zone_rrsets.dmarc = {
          zone = domain;
          name = "_dmarc";
          type = "TXT";
          records = [ { value = ''"v=DMARC1; p=none; rua=mailto:postmaster@${domain}"''; } ];
        };
        zone_rrsets.apex_txt = {
          zone = domain;
          name = "@";
          type = "TXT";
          records = [
            { value = ''"v=spf1 mx ~all"''; }
            { value = ''"google-site-verification=krouLLrAV68-Bw5gN7qr8oN-u_tq5g5bqA9bn1U7z3o"''; }
          ];
        };
      };
    }
  ];
}
