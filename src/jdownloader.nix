{
  systems.x1e.modules = [
    {
      home-manager.users.aforemny.imports = [
        (
          { config, pkgs, ... }:
          let
            # Not in nixpkgs. JDownloader updates itself in place, so instead of
            # a store-pinned jar (whose upstream URL is unversioned), bootstrap
            # the official one into a writable dir on first run.
            dir = "${config.xdg.dataHome}/jdownloader";
            jdownloader = pkgs.writeShellApplication {
              name = "jdownloader";
              runtimeInputs = [
                pkgs.curl
                pkgs.jq
                pkgs.jre
              ];
              text = ''
                mkdir -p "${dir}"
                if [ ! -s "${dir}/JDownloader.jar" ]; then
                  curl -fL -o "${dir}/JDownloader.jar.tmp" \
                    https://installer.jdownloader.org/JDownloader.jar
                  mv "${dir}/JDownloader.jar.tmp" "${dir}/JDownloader.jar"
                fi
                # Java AWT under a tiling compositor (niri via xwayland-satellite).
                export _JAVA_AWT_WM_NONREPARENTING=1
                # xwayland-satellite hands X clients the output's native
                # resolution, so Swing must scale itself to niri's output scale.
                # JAVA_TOOL_OPTIONS (not a -D flag) so the JVM JDownloader
                # relaunches after a self-update inherits it too.
                scale=$(niri msg --json focused-output 2>/dev/null | jq -r '.logical.scale // 1' || echo 1)
                export JAVA_TOOL_OPTIONS="-Dsun.java2d.uiScale=$scale ''${JAVA_TOOL_OPTIONS:-}"
                exec java -jar "${dir}/JDownloader.jar" "$@"
              '';
            };
          in
          {
            home.packages = [
              jdownloader
              (pkgs.makeDesktopItem {
                name = "jdownloader";
                desktopName = "JDownloader";
                exec = "jdownloader";
                categories = [ "Network" ];
              })
            ];
            state.directories = [ ".local/share/jdownloader" ];
          }
        )
      ];
    }
  ];
}
