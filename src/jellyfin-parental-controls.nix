{
  # Parental controls for the children's Jellyfin accounts.
  #
  # The accounts themselves are Keycloak users (src/jellyfin-ldap.nix) that
  # sign in through the LDAP-Auth plugin, which would create them on first
  # login with an unrestricted policy. Instead, this oneshot pre-creates each
  # child's Jellyfin account with LDAP-Auth as its authentication provider
  # (the plugin then adopts it by username on first login) and the parental
  # policy already applied, so the restriction holds from the very first
  # session. The hourly timer re-asserts the policy, undoing edits in the UI.
  #
  # Not the runtime pairing's `users` resource: terraform-provider-jellyfin
  # v0.1.0 reads policy_json back as the *full* server policy, so a partial
  # policy fails the second reconcile with "inconsistent result after apply",
  # and its policy struct predates MaxParentalSubRating.
  #
  # maxRating is Jellyfin's rating score, which follows the age: G/TV-Y and
  # FSK 0 are 0, TV-Y7 7, FSK 6 6, PG 10, FSK 12 12, PG-13 13 (see
  # /Localization/ParentalRatings). Unrated movies, shows and trailers are
  # hidden, so titles with missing metadata cannot slip through; fix their
  # identification to make them visible.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        children = {
          tapostol.maxRating = 7;
          kapostol.maxRating = 7;
        };
        blockUnrated = [
          "Movie"
          "Series"
          "Trailer"
        ];

        inherit (config.services.jellyfin.runtime) baseUrl adminUsername;
        # Minted by the runtime pairing's declarative-jellyfin-password.service
        # (no module option exposes the path).
        adminPasswordFile = "/var/lib/declarative-jellyfin-password/admin-password";
        ldapProvider = "Jellyfin.Plugin.LDAP_Auth.LdapAuthenticationProviderPlugin";

        policies = lib.mapAttrs (_: child: {
          IsAdministrator = false;
          AuthenticationProviderId = ldapProvider;
          MaxParentalRating = child.maxRating;
          MaxParentalSubRating = null;
          BlockUnratedItems = blockUnrated;
        }) children;
        policiesFile = pkgs.writeText "jellyfin-parental-policies.json" (builtins.toJSON policies);
      in
      {
        systemd.services.jellyfin-parental-controls = {
          description = "Apply parental controls to the children's Jellyfin accounts";
          after = [
            "jellyfin.service"
            "declarative-jellyfin-password.service"
          ];
          requires = [ "declarative-jellyfin-password.service" ];
          bindsTo = [ "jellyfin.service" ];
          wantedBy = [ "jellyfin.service" ];
          path = [
            pkgs.curl
            pkgs.jq
          ];
          serviceConfig = {
            Type = "oneshot";
            DynamicUser = true;
            LoadCredential = [ "admin-password:${adminPasswordFile}" ];
          };
          script = ''
            set -euo pipefail
            base=${lib.escapeShellArg baseUrl}
            client='MediaBrowser Client="parental-controls", Device="tower", DeviceId="jellyfin-parental-controls", Version="1"'

            for _ in $(seq 60); do
              curl -fsS "$base/System/Info/Public" >/dev/null 2>&1 && break
              sleep 2
            done

            token=$(jq -n \
                --arg u ${lib.escapeShellArg adminUsername} \
                --rawfile p "$CREDENTIALS_DIRECTORY/admin-password" \
                '{Username: $u, Pw: ($p | rtrimstr("\n"))}' |
              curl -fsS -X POST -H "Authorization: $client" -H 'Content-Type: application/json' \
                --data @- "$base/Users/AuthenticateByName" |
              jq -r .AccessToken)
            auth="Authorization: $client, Token=\"$token\""
            trap 'curl -fsS -o /dev/null -X POST -H "$auth" "$base/Sessions/Logout" || true' EXIT

            users=$(curl -fsS -H "$auth" "$base/Users")
            for name in $(jq -r 'keys[]' ${policiesFile}); do
              id=$(jq -r --arg n "$name" '.[] | select(.Name == $n) | .Id' <<<"$users")
              if [ -z "$id" ]; then
                echo "creating $name"
                id=$(jq -n --arg n "$name" '{Name: $n}' |
                  curl -fsS -X POST -H "$auth" -H 'Content-Type: application/json' \
                    --data @- "$base/Users/New" |
                  jq -r .Id)
              fi
              curl -fsS -H "$auth" "$base/Users/$id" |
                jq --slurpfile p ${policiesFile} --arg n "$name" '.Policy + $p[0][$n]' |
                curl -fsS -X POST -H "$auth" -H 'Content-Type: application/json' \
                  --data @- "$base/Users/$id/Policy"
              echo "applied parental controls to $name"
            done
          '';
        };

        systemd.timers.jellyfin-parental-controls = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
          };
        };
      }
    )
  ];
}
