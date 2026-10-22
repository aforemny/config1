{
  # Grafana at https://grafana.nomath.org, on Prometheus' node metrics from
  # every host (scraped over the management VPN, see src/mvpn.nix).
  #
  # AUTH. Keycloak only, via Grafana's generic OAuth: the login form and basic
  # auth are off, and role_attribute_strict refuses anyone outside the realm's
  # `admins` group (declared in src/oauth2-proxy.nix). The local `admin`
  # account still exists (password below) but cannot log in while the login
  # form is disabled.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "grafana.nomath.org";
        port = 3000;
        realm = "nomath";
        issuer = "https://keycloak.nomath.org/realms/${realm}";
        clientId = "grafana";
        callbackUrl = "https://${fqdn}/login/generic_oauth";
        credentials = "/run/credentials/grafana.service";
        ns = config.vpnNamespaces.mvpn;
        datasource = {
          type = "prometheus";
          uid = "prometheus";
        };

        # Machines dashboard: one row per host with the few numbers that
        # matter (is it up, is anything failed, is anything full), then their
        # history. Root-ish filesystems only; pseudo filesystems are noise.
        fs = ''fstype!~"tmpfs|ramfs|devtmpfs|overlay|squashfs|vfat|efivarfs|fuse.*"'';
        net = ''device!~"lo|veth.*|.*-br|br.*|mvpn.*|tvpn.*|babel.*"'';
        queries = {
          up = ''max by (instance) (up{job="node"})'';
          uptime = "max by (instance) (time() - node_boot_time_seconds)";
          cpu = ''100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval])))'';
          memory = "100 * (1 - max by (instance) (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))";
          disk = "max by (instance) (100 * (1 - node_filesystem_avail_bytes{${fs}} / node_filesystem_size_bytes{${fs}}))";
          failed = ''sum by (instance) (node_systemd_unit_state{state="failed"})'';
          network = "sum by (instance) (rate(node_network_receive_bytes_total{${net}}[$__rate_interval]) + rate(node_network_transmit_bytes_total{${net}}[$__rate_interval]))";
        };
        percent = {
          unit = "percent";
          min = 0;
          max = 100;
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "orange";
                value = 80;
              }
              {
                color = "red";
                value = 90;
              }
            ];
          };
        };
        override = name: properties: {
          matcher = {
            id = "byName";
            options = name;
          };
          properties = lib.mapAttrsToList (id: value: { inherit id value; }) properties;
        };
        colored = {
          "custom.cellOptions".type = "color-text";
        };
        timeseries = title: gridPos: expr: defaults: {
          type = "timeseries";
          inherit title gridPos datasource;
          targets = [
            {
              refId = "A";
              inherit expr;
              legendFormat = "{{instance}}";
            }
          ];
          fieldConfig = {
            defaults = defaults // {
              custom.fillOpacity = 0;
            };
            overrides = [ ];
          };
          options = {
            legend = {
              displayMode = "table";
              placement = "right";
              calcs = [
                "mean"
                "max"
              ];
            };
            tooltip = {
              mode = "multi";
              sort = "desc";
            };
          };
        };
        columns = [
          {
            name = "Up";
            expr = queries.up;
          }
          {
            name = "Failed units";
            expr = queries.failed;
          }
          {
            name = "Fullest filesystem";
            expr = queries.disk;
          }
          {
            name = "Memory";
            expr = queries.memory;
          }
          {
            name = "CPU";
            expr = queries.cpu;
          }
          {
            name = "Uptime";
            expr = queries.uptime;
          }
        ];
        refIds = lib.genList (i: builtins.substring i 1 "ABCDEFGHIJ") (lib.length columns);
        dashboard = {
          uid = "machines";
          title = "Machines";
          schemaVersion = 39;
          refresh = "1m";
          time = {
            from = "now-24h";
            to = "now";
          };
          panels = [
            {
              type = "table";
              title = "Machines";
              gridPos = {
                x = 0;
                y = 0;
                w = 16;
                h = 8;
              };
              inherit datasource;
              targets = lib.zipListsWith (refId: column: {
                inherit refId;
                inherit (column) expr;
                instant = true;
                format = "table";
              }) refIds columns;
              transformations = [
                { id = "merge"; }
                {
                  id = "organize";
                  options = {
                    excludeByName.Time = true;
                    renameByName = lib.listToAttrs (
                      lib.zipListsWith (refId: column: lib.nameValuePair "Value #${refId}" column.name) refIds columns
                    );
                  };
                }
              ];
              fieldConfig = {
                defaults = { };
                overrides = [
                  (override "Up" (
                    colored
                    // {
                      mappings = [
                        {
                          type = "value";
                          options = {
                            "0" = {
                              text = "down";
                              color = "red";
                            };
                            "1" = {
                              text = "up";
                              color = "green";
                            };
                          };
                        }
                      ];
                    }
                  ))
                  (override "Failed units" (
                    colored
                    // {
                      thresholds = {
                        mode = "absolute";
                        steps = [
                          {
                            color = "green";
                            value = null;
                          }
                          {
                            color = "red";
                            value = 1;
                          }
                        ];
                      };
                    }
                  ))
                  (override "Fullest filesystem" (colored // percent // { decimals = 0; }))
                  (override "Memory" (colored // percent // { decimals = 0; }))
                  (override "CPU" (colored // percent // { decimals = 0; }))
                  (override "Uptime" { unit = "s"; })
                ];
              };
              options.sortBy = [
                {
                  displayName = "instance";
                  desc = false;
                }
              ];
            }
            {
              type = "table";
              title = "Failed units";
              gridPos = {
                x = 16;
                y = 0;
                w = 8;
                h = 8;
              };
              inherit datasource;
              targets = [
                {
                  refId = "A";
                  expr = ''node_systemd_unit_state{state="failed"} == 1'';
                  instant = true;
                  format = "table";
                }
              ];
              transformations = [
                {
                  id = "organize";
                  options = {
                    includeByName = {
                      instance = true;
                      name = true;
                    };
                    renameByName.name = "unit";
                  };
                }
              ];
            }
            (timeseries "CPU" {
              x = 0;
              y = 8;
              w = 12;
              h = 8;
            } queries.cpu percent)
            (timeseries "Memory" {
              x = 12;
              y = 8;
              w = 12;
              h = 8;
            } queries.memory percent)
            (timeseries "Fullest filesystem" {
              x = 0;
              y = 16;
              w = 12;
              h = 8;
            } queries.disk percent)
            (timeseries "Network (in + out)" {
              x = 12;
              y = 16;
              w = 12;
              h = 8;
            } queries.network { unit = "Bps"; })
          ];
        };
      in
      {
        age.secrets = {
          # alnum-nonl: Keycloak compares the client secret byte-for-byte (see
          # agenix-rekey.nix).
          grafana-oauth2-client-secret.generator.script = "alnum-nonl";
          grafana-secret-key.generator.script = "alnum-nonl";
          grafana-admin-password.generator.script = "alnum-nonl";
        };

        services.grafana = {
          enable = true;
          settings = {
            server = {
              http_addr = "127.0.0.1";
              http_port = port;
              domain = fqdn;
              root_url = "https://${fqdn}/";
            };
            security = {
              secret_key = "$__file{${credentials}/secret-key}";
              admin_password = "$__file{${credentials}/admin-password}";
              cookie_secure = true;
            };
            analytics.reporting_enabled = false;
            users.allow_sign_up = false;
            auth.disable_login_form = true;
            "auth.basic".enabled = false;
            "auth.generic_oauth" = {
              enabled = true;
              name = "Keycloak";
              client_id = clientId;
              client_secret = "$__file{${credentials}/oauth2-client-secret}";
              scopes = "openid profile email";
              auth_url = "${issuer}/protocol/openid-connect/auth";
              token_url = "${issuer}/protocol/openid-connect/token";
              api_url = "${issuer}/protocol/openid-connect/userinfo";
              use_pkce = true;
              auto_login = true;
              allow_sign_up = true;
              login_attribute_path = "preferred_username";
              name_attribute_path = "name";
              email_attribute_path = "email";
              groups_attribute_path = "groups";
              # Admins only: no role for anyone else, and strict mode turns a
              # missing role into a refused login.
              role_attribute_path = "contains(groups[*], 'admins') && 'Admin'";
              role_attribute_strict = true;
            };
          };
          provision = {
            enable = true;
            datasources.settings = {
              apiVersion = 1;
              datasources = [
                (
                  datasource
                  // {
                    name = "Prometheus";
                    access = "proxy";
                    url = "http://${ns.namespaceAddress}:${toString config.services.prometheus.port}";
                    isDefault = true;
                  }
                )
              ];
            };
            dashboards.settings.providers = [
              {
                name = "nomath";
                options.path = pkgs.writeTextDir "machines.json" (builtins.toJSON dashboard);
              }
            ];
          };
        };

        systemd.services.grafana.serviceConfig.LoadCredential = [
          "oauth2-client-secret:${config.age.secrets.grafana-oauth2-client-secret.path}"
          "secret-key:${config.age.secrets.grafana-secret-key.path}"
          "admin-password:${config.age.secrets.grafana-admin-password.path}"
        ];

        services.keycloak.runtime = {
          openid_clients.${clientId} = {
            inherit realm;
            enabled = true;
            access_type = "CONFIDENTIAL";
            standard_flow_enabled = true;
            valid_redirect_uris = [ callbackUrl ];
            web_origins = [ "https://${fqdn}" ];
            client_secretFile = config.age.secrets.grafana-oauth2-client-secret.path;
          };
          openid_group_membership_protocol_mappers.${clientId} = {
            inherit realm;
            client = clientId;
            claim_name = "groups";
            full_path = false;
            add_to_id_token = true;
            add_to_access_token = true;
            add_to_userinfo = true;
          };
        };

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              proxyWebsockets = true;
              recommendedProxySettings = true;
            };
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "grafana" ];

        # The module creates /var/lib/grafana as the user's home (not via
        # StateDirectory=), so it needs impermanence's ownership form.
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/grafana";
            user = "grafana";
            group = "grafana";
            mode = "0700";
          }
        ];
        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
