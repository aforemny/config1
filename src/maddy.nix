{
  # Maddy mail server on tower for nomath.org, authenticating users against the
  # shared lldap directory (src/ldap.nix) -- the same account store Keycloak
  # federates. maddy speaks SMTP/IMAP directly; nginx is only borrowed for the
  # ACME HTTP-01 challenge that mints the mail TLS certificate.
  #
  # Identity model: users log in with their full email address. maddy binds to
  # lldap as the shared admin, searches for the entry whose uid or mail matches,
  # then rebinds as that entry to verify the password. The address the user
  # supplied becomes the mailbox identity, so the IMAP mailbox and the SMTP
  # delivery address are the same string. imapsql creates the mailbox lazily
  # (GetOrCreateUser) on first login or first delivery, so no account list is
  # declared here -- lldap remains the sole source of accounts.
  #
  # External DNS still has to be provisioned at the registrar (out of scope for
  # dns.dynamicAAAA, which only manages the AAAA record): an MX for nomath.org
  # -> mail.nomath.org, an SPF TXT, the DKIM TXT that maddy prints on first
  # start, a DMARC TXT, and a PTR for the host's IPv6 address. Without these,
  # remote servers will reject mail from this host.
  systems.tower.modules = [
    (
      { config, ... }:
      let
        fqdn = "mail.nomath.org";
        domain = "nomath.org";
        # Shared bind credential, declared once in src/ldap.nix.
        bindDn = "uid=admin,ou=people,dc=nomath,dc=org";
        bindPasswordFile = config.age.secrets.lldap-admin-password.path;
      in
      {
        services.maddy = {
          enable = true;
          hostname = fqdn;
          primaryDomain = domain;
          localDomains = [ domain ];
          openFirewall = true; # 25 (SMTP), 143 (IMAP+STARTTLS), 587 (submission)

          # TLS from the ACME certificate obtained below. On renewal the acme
          # module try-reload-or-restarts maddy, which re-reads the pair.
          tls = {
            loader = "file";
            certificates = [
              {
                certPath = "/var/lib/acme/${fqdn}/fullchain.pem";
                keyPath = "/var/lib/acme/${fqdn}/key.pem";
              }
            ];
          };

          # The bind password reaches maddy as $LLDAP_BIND_PW through the
          # EnvironmentFile rendered below, and is referenced in the config with
          # maddy's {env:...} expansion.
          secrets = [ "/run/maddy-ldap/env" ];

          # Upstream's default pipeline with the pass_table auth backend swapped
          # for auth.ldap against lldap. The NixOS module prepends the
          # $(hostname)/$(primary_domain)/$(local_domains) macros and the tls
          # block, so this body starts at the auth module.
          config = ''
            auth.ldap local_authdb {
              urls ldap://127.0.0.1:3890
              bind plain "${bindDn}" "{env:LLDAP_BIND_PW}"
              base_dn "ou=people,dc=nomath,dc=org"
              filter "(&(objectClass=person)(|(uid={username})(mail={username})))"
              starttls off
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
                    dkim $(primary_domain) $(local_domains) default
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

        # Render maddy's EnvironmentFile from the agenix secret at runtime so the
        # bind password never lands in the world-readable store (mirrors the
        # keycloak-bootstrap-admin-env pattern in src/keycloak.nix).
        systemd.services.maddy-ldap-env = {
          description = "Render maddy's lldap bind EnvironmentFile from the agenix secret";
          requiredBy = [ "maddy.service" ];
          before = [ "maddy.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            LoadCredential = [ "bind:${bindPasswordFile}" ];
            RuntimeDirectory = "maddy-ldap";
            RuntimeDirectoryMode = "0700";
          };
          script = ''
            set -euo pipefail
            umask 077
            printf 'LLDAP_BIND_PW=%s\n' "$(cat "$CREDENTIALS_DIRECTORY/bind")" \
              > "$RUNTIME_DIRECTORY/env"
          '';
        };

        # ACME certificate for the mail hostname, obtained via the HTTP-01
        # webroot challenge that nginx (already on tower for keycloak/jellyfin)
        # serves over :80. maddy is the only consumer, so nginx is deliberately
        # kept out of the cert's reloadServices and the key is owned by the
        # maddy group -- nginx never reads it. maddy is try-reload-or-restarted
        # on renewal. The cert's own systemd unit is ordered after nginx so the
        # challenge is servable on first issuance.
        services.nginx = {
          enable = true;
          virtualHosts.${fqdn}.locations."/.well-known/acme-challenge".root = "/var/lib/acme/acme-challenge";
        };
        security.acme = {
          acceptTerms = true;
          defaults.email = "aforemny@posteo.de";
          certs.${fqdn} = {
            webroot = "/var/lib/acme/acme-challenge";
            group = "maddy";
            reloadServices = [ "maddy.service" ];
          };
        };
        systemd.services."acme-${fqdn}" = {
          after = [ "nginx.service" ];
          wants = [ "nginx.service" ];
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Published as mail.nomath.org by src/dns.nix; the MX record itself is
        # provisioned manually at the registrar (see the header).
        dns.dynamicAAAA = [ "mail" ];

        # tower rolls / back on boot; persist the mailboxes, IMAP index, DKIM
        # keys and MTA-STS cache (all under /var/lib/maddy) plus the TLS material.
        state.directories = [
          "/var/lib/maddy"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
