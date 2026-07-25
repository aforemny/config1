{
  # Home Assistant on tower, reachable at https://ha.nomath.org. nginx
  # terminates TLS and reverse-proxies to a loopback-only Home Assistant.
  #
  # Authentication is delegated to Keycloak (realm `nomath`, the same realm the
  # lldap federation and Jellyfin users live in -- see src/jellyfin-ldap.nix /
  # src/ldap.nix). Home Assistant has no native OIDC, so the community
  # relying-party integration `hass-oidc-auth` (christiaangoossens) is packaged
  # from source as a custom component; it adds an OIDC auth provider that speaks
  # the standard authorization-code + PKCE flow against Keycloak.
  #
  # The Keycloak side (OIDC client, group, and groups-claim mapper) is declared
  # under services.keycloak.runtime below and reconciled by the
  # declarative-runtime layer that src/keycloak.nix already wires up.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "ha.nomath.org";
        port = 8123;
        realm = "nomath";
        clientId = "homeassistant";
        # Only members of this Keycloak group may sign in, and they receive
        # admin rights (roles.user == roles.admin, so the group gates access).
        adminGroup = "homeassistant-admins";

        # hass-oidc-auth v1.1.1, packaged straight from the tagged source. Its
        # manifest requirements (aiofiles, jinja2, joserfc) are all in HA's
        # python set; the build hook verifies they are present.
        hass-oidc-auth = pkgs.buildHomeAssistantComponent {
          owner = "christiaangoossens";
          domain = "auth_oidc";
          version = "1.1.1";
          src = pkgs.fetchFromGitHub {
            owner = "christiaangoossens";
            repo = "hass-oidc-auth";
            rev = "v1.1.1";
            hash = "sha256-d1nRSAR4HAoW+gpAtyb0s6bh40CcoT59dgVOkwKHavU=";
          };
          propagatedBuildInputs = with pkgs.home-assistant.python3Packages; [
            aiofiles
            jinja2
            joserfc
          ];
        };
      in
      {
        services.home-assistant = {
          enable = true;
          customComponents = [ hass-oidc-auth ];
          extraComponents = [
            "default_config"
            "met"
          ];
          config = {
            homeassistant = {
              external_url = "https://${fqdn}";
              # Core config seeded so the skipped onboarding never needs to
              # prompt for it. Germany/metric, matching time.timeZone =
              # Europe/Berlin (src/tz.nix); time_zone itself is injected from
              # that by the NixOS module. latitude/longitude/elevation are set
              # below to place the home on the map (sun, weather, etc.).
              unit_system = "metric";
              currency = "EUR";
              country = "DE";
              # Hannover, Germany (city centre).
              latitude = 52.3759;
              longitude = 9.732;
              elevation = 55;
            };
            default_config = { };

            # nginx is the only client; bind loopback and trust its forwarded
            # headers so client IP / scheme are correct behind the proxy.
            http = {
              server_host = [
                "127.0.0.1"
                "::1"
              ];
              use_x_forwarded_for = true;
              trusted_proxies = [
                "127.0.0.1"
                "::1"
              ];
            };

            # OpenID Connect / SSO via Keycloak. Public client + PKCE, no client
            # secret (upstream-recommended for a home setup: PKCE + a fixed
            # redirect URI already give sufficient security, and there is no
            # secret to leak). Access is gated to the `${adminGroup}` group.
            auth_oidc = {
              client_id = clientId;
              discovery_url = "https://keycloak.nomath.org/realms/${realm}/.well-known/openid-configuration";
              display_name = "nomath.org SSO";
              # TLS ends at nginx; force HTTPS when building callback URLs.
              # default_redirect skips the welcome screen and sends users
              # straight to Keycloak (no local password login exists anyway).
              features = {
                force_https = true;
                default_redirect = true;
              };
              roles = {
                admin = adminGroup;
                user = adminGroup;
              };
            };
          };
        };

        # Skip Home Assistant's onboarding wizard. HA's onboarding integration
        # (homeassistant/components/onboarding) treats the instance as fully
        # onboarded -- and never registers the wizard -- as soon as
        # .storage/onboarding lists every step as done, even with zero users.
        # With onboarding out of the way the login screen is served directly and
        # the first Keycloak sign-in creates the account: hass-oidc-auth sets
        # UserMeta(is_active=True, group="system-admin") for a user in the
        # `homeassistant-admins` group, so aforemny lands as an active admin (HA
        # Core has no separate "owner" gate that matters here). Seeded only if
        # absent, so runtime changes under the persisted /var/lib/hass survive.
        systemd.services.home-assistant.preStart = lib.mkAfter ''
          storageDir="${config.services.home-assistant.configDir}/.storage"
          if [ ! -e "$storageDir/onboarding" ]; then
            mkdir -p "$storageDir"
            cat > "$storageDir/onboarding" <<'EOF'
          {"version":4,"minor_version":1,"key":"onboarding","data":{"done":["user","core_config","analytics","integration"]}}
          EOF
          fi
        '';

        services.nginx = {
          enable = true;
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString port}";
              proxyWebsockets = true; # HA frontend uses websockets
              recommendedProxySettings = true;
            };
          };
        };

        security.acme = {
          acceptTerms = true;
          defaults.email = "aforemny@posteo.de";
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        # Published as ha.nomath.org by src/dns.nix.
        dns.dynamicAAAA = [ "ha" ];

        # Keycloak runtime state for the HA login: a public OIDC client, the
        # admin group with aforemny in it, and a groups-claim mapper. Reconciled
        # via OpenTofu after keycloak.service is up (see src/keycloak.nix).
        services.keycloak.runtime = {
          openid_clients.${clientId} = {
            realm = realm;
            client_id = clientId;
            name = "Home Assistant";
            enabled = true;
            # Public client: PKCE-protected authorization-code flow, no secret.
            access_type = "PUBLIC";
            standard_flow_enabled = true;
            pkce_code_challenge_method = "S256";
            valid_redirect_uris = [ "https://${fqdn}/auth/oidc/callback" ];
            valid_post_logout_redirect_uris = [ "https://${fqdn}/*" ];
            web_origins = [ "https://${fqdn}" ];
          };

          groups.${adminGroup} = {
            realm = realm;
            name = adminGroup;
            description = "Home Assistant administrators";
          };

          # aforemny is a managed realm user (src/jellyfin-ldap.nix); resolve the
          # key to its username and add it to the admin group.
          group_memberships.${adminGroup} = {
            realm = realm;
            group = adminGroup;
            members = [ "aforemny" ];
          };

          # hass-oidc-auth requests the `groups` scope and reads the `groups`
          # claim (leaf names, full_path off) to resolve roles. Emit it via a
          # dedicated client scope attached to the HA client as a default scope.
          openid_client_scopes.homeassistant-groups = {
            realm = realm;
            name = "groups";
            description = "Group memberships for Home Assistant role mapping";
          };

          openid_group_membership_protocol_mappers.homeassistant-groups = {
            realm = realm;
            client_scope = "homeassistant-groups";
            name = "groups";
            claim_name = "groups";
            full_path = false;
            add_to_id_token = true;
            add_to_access_token = true;
            add_to_userinfo = true;
          };

          # keycloak_openid_client_default_scopes replaces the client's full
          # default-scope set, so re-list Keycloak's built-in defaults alongside
          # our `groups` scope to avoid dropping the essential claims (basic ->
          # sub, profile -> preferred_username/name, email).
          openid_client_default_scopes.homeassistant = {
            realm = realm;
            client = clientId;
            default_scopes = [
              "homeassistant-groups"
              "basic"
              "profile"
              "email"
              "roles"
              "web-origins"
              "acr"
            ];
          };
        };

        # tower rolls / back on boot; persist HA state. /var/lib/hass is the
        # hass user's home (createHome=true), not a StateDirectory=, so under
        # impermanence create the /persist source owned by hass -- a bare-string
        # entry would be root:root and HA could not write (same reasoning as
        # src/jellyfin.nix).
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/hass";
            user = "hass";
            group = "hass";
            mode = "0700";
          }
        ];

        state.directories = [
          "/var/lib/acme" # nginx TLS certificates
        ];
      }
    )
  ];
}
