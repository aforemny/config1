{
  # Derivation-accurate CVE scanning. vulnix reads the derivation behind every
  # store path in the running system closure, extracts each component's real
  # (name, version), and matches it against the NVD feeds -- no CPE-string
  # guessing, so it does not suffer the false negatives a keyword/CPE query does.
  #
  # DERIVATIONS. Hosts built elsewhere and copied over (all but x1e) have the
  # outputs but not the .drv files vulnix reads, so `vulnix -S` fails there.
  # The system therefore carries the derivations of its main parts (/etc with
  # every unit, the package set, kernel, modules, initrd, firmware): their
  # paths are written into the toplevel, which makes the .drv files part of
  # its closure. The toplevel's own .drv cannot be included (it would have to
  # contain its own hash), so the scan starts from those parts with `-C`,
  # which follows their runtime closures. This costs a few hundred MiB per
  # host, mostly .drv files and the sources they reference.
  #
  # The scan runs daily on EVERY host (this is a `nixosModules.*`, so it applies
  # fleet-wide like src/ssh.nix) and writes Prometheus metrics into the node
  # exporter's textfile collector directory. The node exporter (src/mvpn.nix)
  # already listens on each host's mvpn address and is scraped by the confined
  # Prometheus on tower, so the `vulnix_*` metrics reach Prometheus -- and thus
  # Grafana -- fleet-wide with no extra scrape config. A Grafana dashboard
  # (tower only, below) renders them.
  nixosModules.vulnix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      textfileDir = "/var/lib/prometheus-node-exporter-textfile";
      stateDir = "/var/lib/vulnix";
      # The parts of the system the scan starts from (see DERIVATIONS above).
      roots = [
        config.system.build.etc
        config.system.path
      ]
      ++ lib.toList config.system.modulesTree
      ++ lib.toList config.hardware.firmware
      ++ lib.optional (config.system.build ? initialRamdisk) config.system.build.initialRamdisk;
    in
    {
      system.systemBuilderCommands = ''
        printf '%s\n' ${
          lib.escapeShellArgs (map (root: builtins.unsafeDiscardOutputDependency root.drvPath) roots)
        } > $out/vulnix-derivations
        printf '%s\n' ${lib.escapeShellArgs roots} > $out/vulnix-roots
      '';

      # Expose the textfile collector on the node exporter. enabledCollectors /
      # extraFlags are list options, so these MERGE with src/mvpn.nix's
      # `enabledCollectors = [ "systemd" ]` rather than replacing it.
      services.prometheus.exporters.node = {
        enabledCollectors = [ "textfile" ];
        extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
      };

      systemd.tmpfiles.rules = [
        "d ${textfileDir} 0755 root root - -"
      ];

      systemd.services.vulnix-scan = {
        description = "Scan the running system closure for known CVEs (vulnix)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.vulnix
          pkgs.jq
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          # Root: vulnix must read the whole closure and reach NVD; it only reads
          # the store. Hardened below. Not DynamicUser so the persisted NVD cache
          # (below) keeps a stable owner across tower's rootfs rollback.
          # vulnix fetches ~yearly NVD archives; they are cached under the
          # (persisted) state directory, so a daily run does an incremental
          # update instead of a full re-download.
          StateDirectory = "vulnix";
          # Writes only the metric file and its own state/cache.
          ReadWritePaths = [
            textfileDir
            stateDir
          ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
        };
        script = ''
          set -uo pipefail
          report="$STATE_DIRECTORY/report.json"
          out="${textfileDir}/vulnix.prom"
          tmp="$(mktemp "${textfileDir}/.vulnix.prom.XXXXXX")"
          trap 'rm -f "$tmp"' EXIT
          now="$(date +%s)"

          # Roots the current system has (firmware, say, may only be present
          # in compressed form).
          roots=()
          while read -r root; do
            [ -e "$root" ] && roots+=("$root")
          done < /run/current-system/vulnix-roots

          # vulnix exit codes: 0 = no vulnerabilities, 2 = vulnerabilities found,
          # 1 (or other) = error. Both 0 and 2 produce valid JSON. NixOS runs this
          # script with `set -e`, so catch the status instead of exiting on it.
          rc=0
          vulnix -C --json --cache-dir "$STATE_DIRECTORY/cache" "''${roots[@]}" \
            > "$report" 2>"$STATE_DIRECTORY/stderr" || rc=$?

          {
            echo "# HELP vulnix_scan_success Whether the last vulnix run completed and parsed (1) or failed (0)."
            echo "# TYPE vulnix_scan_success gauge"
            echo "# HELP vulnix_last_run_timestamp_seconds Unix time the last vulnix run finished."
            echo "# TYPE vulnix_last_run_timestamp_seconds gauge"
            echo "# HELP vulnix_affected_derivations Store paths in the closure with >=1 non-whitelisted CVE."
            echo "# TYPE vulnix_affected_derivations gauge"
            echo "# HELP vulnix_cves_total Distinct CVE IDs affecting the system closure."
            echo "# TYPE vulnix_cves_total gauge"
            echo "# HELP vulnix_max_cvss Highest CVSSv3 base score among affected packages."
            echo "# TYPE vulnix_max_cvss gauge"
            echo "# HELP vulnix_cves_by_severity Distinct CVEs bucketed by CVSSv3 severity."
            echo "# TYPE vulnix_cves_by_severity gauge"
            echo "vulnix_last_run_timestamp_seconds $now"

            if { [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; } && jq -e . "$report" >/dev/null 2>&1; then
              echo "vulnix_scan_success 1"
              jq -r '
                [ .[] ]                                             as $pkgs
                | ( [ $pkgs[] | .affected_by[]? ] | unique )        as $cves
                | ( reduce $pkgs[] as $p ({};
                      reduce ($p.cvssv3_basescore // {} | to_entries[]) as $e (.;
                        .[$e.key] = ([ .[$e.key], $e.value ] | map(select(. != null)) | (max // null)))) ) as $score
                | ( [ $cves[] | $score[.] ] )                       as $sev
                | ( [ $sev[] | select(. != null) ] )                as $scored
                | "vulnix_affected_derivations \([ $pkgs[] | select((.affected_by // []) | length > 0) ] | length)",
                  "vulnix_cves_total \($cves | length)",
                  "vulnix_max_cvss \((($scored) + [0]) | max)",
                  "vulnix_cves_by_severity{severity=\"critical\"} \([ $scored[] | select(. >= 9.0) ] | length)",
                  "vulnix_cves_by_severity{severity=\"high\"} \([ $scored[] | select(. >= 7.0 and . < 9.0) ] | length)",
                  "vulnix_cves_by_severity{severity=\"medium\"} \([ $scored[] | select(. >= 4.0 and . < 7.0) ] | length)",
                  "vulnix_cves_by_severity{severity=\"low\"} \([ $scored[] | select(. > 0.0 and . < 4.0) ] | length)",
                  "vulnix_cves_by_severity{severity=\"unknown\"} \([ $sev[] | select(. == null) ] | length)"
              ' "$report"
            else
              echo "vulnix_scan_success 0"
            fi
          } > "$tmp"

          # Atomic publish so the node exporter never reads a half-written file.
          # mktemp creates it 0600, and the node exporter runs as its own user.
          chmod 0644 "$tmp"
          mv -f "$tmp" "$out"
        '';
      };

      systemd.timers.vulnix-scan = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          RandomizedDelaySec = "2h";
          Persistent = true;
        };
      };

      # Keep the NVD cache (and report) across tower's rootfs rollback; a no-op on
      # hosts without /persist.
      state.directories = [ stateDir ];
    };

  # Grafana dashboard for the fleet-wide vulnix metrics. Added as a SECOND
  # dashboard provider (the providers list merges with src/grafana.nix's), so
  # grafana.nix itself is untouched. tower only -- that is where Grafana runs.
  systems.tower.modules = [
    (
      { pkgs, ... }:
      let
        dashboard = {
          title = "Vulnix / CVE exposure";
          uid = "vulnix-fleet";
          schemaVersion = 39;
          time = {
            from = "now-30d";
            to = "now";
          };
          panels = [
            {
              id = 1;
              title = "Highest CVSS per host";
              type = "timeseries";
              gridPos = {
                h = 8;
                w = 12;
                x = 0;
                y = 0;
              };
              targets = [
                {
                  expr = "max by (instance) (vulnix_max_cvss)";
                  legendFormat = "{{instance}}";
                }
              ];
            }
            {
              id = 2;
              title = "Affected derivations per host";
              type = "timeseries";
              gridPos = {
                h = 8;
                w = 12;
                x = 12;
                y = 0;
              };
              targets = [
                {
                  expr = "max by (instance) (vulnix_affected_derivations)";
                  legendFormat = "{{instance}}";
                }
              ];
            }
            {
              id = 3;
              title = "CVEs by severity (fleet)";
              type = "timeseries";
              gridPos = {
                h = 8;
                w = 12;
                x = 0;
                y = 8;
              };
              targets = [
                {
                  expr = "sum by (severity) (vulnix_cves_by_severity)";
                  legendFormat = "{{severity}}";
                }
              ];
            }
            {
              id = 4;
              title = "Scan freshness (hours since last run)";
              type = "timeseries";
              gridPos = {
                h = 8;
                w = 12;
                x = 12;
                y = 8;
              };
              targets = [
                {
                  # node exporter stamps the textfile mtime; also surfaces a
                  # scan that started failing even while the file is fresh.
                  expr = "(time() - max by (instance) (vulnix_last_run_timestamp_seconds)) / 3600";
                  legendFormat = "{{instance}}";
                }
              ];
            }
            {
              id = 5;
              title = "Hosts with a failed/stale scan";
              type = "stat";
              gridPos = {
                h = 8;
                w = 24;
                x = 0;
                y = 16;
              };
              targets = [
                {
                  expr = "count(vulnix_scan_success == 0) or vector(0)";
                  legendFormat = "failing";
                }
              ];
            }
          ];
        };
      in
      {
        services.grafana.provision.dashboards.settings.providers = [
          {
            name = "vulnix";
            options.path = pkgs.writeTextDir "vulnix.json" (builtins.toJSON dashboard);
          }
        ];
      }
    )
  ];
}
