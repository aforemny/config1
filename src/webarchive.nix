{
  # Personal web archive at https://archive.nomath.org.
  #
  # CRAWL. Each site in `sites` gets a `webarchive-<site>` oneshot on a timer:
  # wget crawls the whole site (plain HTTP, no JavaScript) into WARC files, and
  # `wacz create` packs those into one dated WACZ (WARCs + CDXJ index + page
  # list with full-text) under /srv/webarchive/<site>/. Every run is a new,
  # complete snapshot; snapshots are kept forever. wget cannot resume a WARC
  # crawl, so an interrupted run is discarded and the next one starts over.
  #
  # REPLAY. The vhost serves a small landing page that lists the snapshots
  # (nginx JSON autoindex of /snapshots/) and embeds ReplayWeb.page's
  # <replay-web-page>, which replays a WACZ entirely in the browser through
  # range requests -- no server-side replay daemon. Its service worker lives
  # under /replay/ (the component's default `replaybase`).
  #
  # AUTH. The archive republishes other people's content, so the vhost is
  # private: src/oauth2-proxy.nix lists it (Keycloak `admins` only).
  #
  # STORAGE. /srv/webarchive is its own dataset, zdata/local/webarchive (see
  # platforms/tower.nix). disko only creates datasets when formatting, so on
  # the running host create it once before deploying:
  #   zfs create -o mountpoint=/srv/webarchive zdata/local/webarchive
  # It is not under /persist: like /srv/media it survives the rootfs rollback
  # by being its own dataset.
  systems.tower.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        fqdn = "archive.nomath.org";
        root = "/srv/webarchive";

        sites = {
          "seriouseats.com" = {
            url = "https://www.seriouseats.com/";
            # Images are served from www.seriouseats.com/thmb/, so no extra
            # hosts are needed.
            domains = [ "seriouseats.com" ];
            # Site search is a crawler trap; /embed? is disallowed by robots.txt
            # anyway.
            rejectRegex = "/search\\?|/embed\\?";
            # A full crawl takes a day or more at a polite rate.
            schedule = "monthly";
          };
        };

        # nixpkgs' wacz (0.5.0) no longer builds: it imports pkg_resources,
        # which current setuptools dropped, and the test suites of it and its
        # deps want pkg_resources or the broken `certauth`. Only `version()`
        # actually uses pkg_resources; the other imports are dead.
        wacz =
          let
            noCheck =
              p:
              p.overridePythonAttrs {
                doCheck = false;
                nativeCheckInputs = [ ];
              };
            python = pkgs.python3.override {
              self = python;
              packageOverrides = _: psuper: {
                warcio = noCheck psuper.warcio;
                cdxj-indexer = noCheck psuper.cdxj-indexer;
                wacz = (noCheck psuper.wacz).overridePythonAttrs (old: {
                  postPatch = old.postPatch + ''
                    sed -i 's/, pkg_resources//' wacz/main.py wacz/validate.py
                    substituteInPlace wacz/util.py \
                      --replace-fail 'import pkg_resources' 'import importlib.metadata' \
                      --replace-fail 'pkg_resources.get_distribution("wacz").version' 'importlib.metadata.version("wacz")'
                  '';
                });
              };
            };
          in
          python.pkgs.wacz;

        replaywebpage = pkgs.fetchzip {
          url = "https://registry.npmjs.org/replaywebpage/-/replaywebpage-2.5.4.tgz";
          hash = "sha256-bjEMUAFMI9z6dnjL4m2n2uGG7eX45Vv07C6n8SKIVCA=";
        };

        landing = pkgs.writeTextDir "index.html" ''
          <!doctype html>
          <html>
            <head>
              <meta charset="utf-8" />
              <meta name="viewport" content="width=device-width, initial-scale=1" />
              <title>Web archive</title>
              <script src="/replay/ui.js"></script>
              <style>
                html, body { margin: 0; height: 100%; font-family: sans-serif; }
                body { display: flex; flex-direction: column; }
                nav { padding: 0.5em 1em; border-bottom: 1px solid #ccc; }
                nav h1 { font-size: 1.2em; margin: 0.3em 0; }
                nav a { margin-right: 0.8em; }
                nav a.current { font-weight: bold; }
                replay-web-page { flex: 1; }
              </style>
            </head>
            <body>
              <nav><h1><a href="/">Web archive</a></h1><div id="list">Loading…</div></nav>
              <script>
                const ls = async (path, type) =>
                  (await (await fetch(path)).json())
                    .filter((e) => e.type === type)
                    .map((e) => e.name);
                const params = new URLSearchParams(location.search);
                const current = params.get("source");
                (async () => {
                  const list = document.getElementById("list");
                  list.textContent = "";
                  for (const site of await ls("/snapshots/", "directory")) {
                    const row = document.createElement("div");
                    row.append(site + ": ");
                    const snapshots = (await ls("/snapshots/" + site + "/", "file"))
                      .filter((n) => n.endsWith(".wacz"))
                      .sort()
                      .reverse();
                    for (const name of snapshots) {
                      const source = "/snapshots/" + site + "/" + name;
                      const a = document.createElement("a");
                      a.href = "?source=" + encodeURIComponent(source);
                      a.textContent = name.replace(/\.wacz$/, "");
                      if (source === current) a.className = "current";
                      row.append(a);
                    }
                    if (snapshots.length === 0) row.append("no snapshot yet");
                    list.append(row);
                  }
                })();
                if (current) {
                  const replay = document.createElement("replay-web-page");
                  replay.setAttribute("source", current);
                  document.body.append(replay);
                }
              </script>
            </body>
          </html>
        '';

        site = pkgs.runCommand "webarchive-site" { } ''
          mkdir -p $out
          cp ${landing}/index.html $out/
          ln -s ${replaywebpage} $out/replay
        '';

        crawl =
          name: s:
          pkgs.writeShellApplication {
            name = "webarchive-crawl";
            runtimeInputs = [
              pkgs.wget
              wacz
            ];
            text = ''
              dir=${root}/${name}
              ts=$(date -u +%Y-%m-%dT%H%M%SZ)
              work=$dir/.partial
              # Leftovers of an interrupted run: wget cannot resume them.
              rm -rf "$work"
              mkdir -p "$work"
              cd "$work"

              # Exit 8 means some responses were HTTP errors (dead links),
              # which every real site has; anything else is a failed crawl.
              rc=0
              wget \
                --recursive --level=inf --page-requisites \
                --span-hosts --domains=${lib.concatStringsSep "," s.domains} \
                --reject-regex=${lib.escapeShellArg s.rejectRegex} \
                --no-directories --delete-after \
                --wait=1 --random-wait \
                --tries=3 --timeout=60 \
                --user-agent="Mozilla/5.0 (compatible; personal web archive; +https://${fqdn})" \
                --warc-file=crawl --warc-max-size=1G \
                --no-verbose --output-file=wget.log \
                ${lib.escapeShellArg s.url} || rc=$?
              if [ "$rc" -ne 0 ] && [ "$rc" -ne 8 ]; then
                echo "wget failed with exit code $rc" >&2
                tail -n 20 wget.log >&2
                exit "$rc"
              fi

              wacz create --detect-pages --text \
                --url ${lib.escapeShellArg s.url} --title ${lib.escapeShellArg name} \
                -o snapshot.wacz crawl-*.warc.gz
              chmod 0644 snapshot.wacz
              mv snapshot.wacz "$dir/$ts.wacz"
              cd /
              rm -rf "$work"
            '';
          };
      in
      {
        users.users.webarchive = {
          isSystemUser = true;
          group = "webarchive";
        };
        users.groups.webarchive = { };

        systemd.tmpfiles.rules = [
          "d ${root} 0755 webarchive webarchive -"
        ]
        ++ lib.mapAttrsToList (name: _: "d ${root}/${name} 0755 webarchive webarchive -") sites;

        systemd.services = lib.mapAttrs' (
          name: s:
          lib.nameValuePair "webarchive-${name}" {
            description = "Crawl ${name} into the web archive";
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            unitConfig.RequiresMountsFor = [ root ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe (crawl name s);
              User = "webarchive";
              Group = "webarchive";
              # A full crawl runs for a day or more.
              TimeoutStartSec = "infinity";
              Nice = 10;
              IOSchedulingClass = "idle";
              ProtectSystem = "strict";
              ReadWritePaths = [ root ];
              ProtectHome = true;
              PrivateTmp = true;
              NoNewPrivileges = true;
            };
          }
        ) sites;

        systemd.timers = lib.mapAttrs' (
          name: s:
          lib.nameValuePair "webarchive-${name}" {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = s.schedule;
              Persistent = true;
              RandomizedDelaySec = "6h";
            };
          }
        ) sites;

        services.nginx = {
          enable = true;
          # Behind Keycloak: src/oauth2-proxy.nix lists this vhost.
          virtualHosts.${fqdn} = {
            forceSSL = true;
            enableACME = true;
            root = site;
            locations."/snapshots/" = {
              alias = "${root}/";
              extraConfig = ''
                autoindex on;
                autoindex_format json;
              '';
            };
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "archive" ];

        state.directories = [ "/var/lib/acme" ];
      }
    )
  ];
}
