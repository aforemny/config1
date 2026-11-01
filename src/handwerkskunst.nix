{
  # Mirror the SWR Handwerkskunst YouTube channel into tower's Jellyfin
  # library, weekly on Saturdays at 04:00. Only the full episodes (the
  # channel's videos tab), not its Shorts.
  #
  # Episodes land as `Season <year>/SWR Handwerkskunst - <date> - <title>`,
  # which Jellyfin's tvshows library matches by air date. Titles are the
  # German originals (YouTube otherwise serves machine-localised English
  # ones) minus the redundant "| SWR Handwerkskunst" suffix. Best quality is
  # sorted by resolution, fps, then bitrate, which picks the 1080p50 H.264
  # HLS stream: also the one tower's Ivy Bridge iGPU can decode (src/
  # jellyfin.nix). Partial downloads stay in downloads/youtube/tmp so
  # Jellyfin never scans them, and the download archive there makes reruns
  # skip what is already mirrored.
  #
  # Runs as `transmission`, the media stack's shared primary group (see
  # src/servarr.nix), with umask 002 like the rest of /srv/media.
  systems.tower.modules = [
    (
      { lib, pkgs, ... }:
      let
        channel = "https://www.youtube.com/channel/UC4-a6QWRyBlzTFGdS-T_wfw/videos";
        library = "/srv/media/library/tv/SWR Handwerkskunst";
        work = "/srv/media/downloads/youtube";
        template = "Season %(upload_date>%Y)s/SWR Handwerkskunst - %(upload_date>%Y-%m-%d)s - %(title)s [%(id)s]";
      in
      {
        systemd.services.handwerkskunst = {
          description = "Mirror SWR Handwerkskunst into Jellyfin";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          # The library's parent: RequiresMountsFor= splits on the space.
          unitConfig.RequiresMountsFor = [
            "/srv/media/library/tv"
            work
          ];
          serviceConfig = {
            Type = "oneshot";
            User = "transmission";
            Group = "transmission";
            UMask = "0002";
            Nice = 10;
            WorkingDirectory = work;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            ReadWritePaths = [
              "/srv/media/library/tv"
              work
            ];
          };
          script = ''
            # --ignore-errors makes one failed episode exit 1; the next run
            # retries it, so only a total failure should fail the unit.
            ${lib.getExe pkgs.yt-dlp} ${
              lib.escapeShellArgs [
                "--extractor-args"
                "youtube:lang=de"
                "-f"
                "bv*+ba/b"
                "-S"
                "res,fps,br"
                "--merge-output-format"
                "mkv"
                "-N"
                "4"
                "--retries"
                "20"
                "--fragment-retries"
                "20"
                "--sleep-requests"
                "1"
                "--sleep-interval"
                "5"
                "--max-sleep-interval"
                "15"
                "--download-archive"
                "${work}/handwerkskunst.archive"
                "--replace-in-metadata"
                "title"
                "\\s*[|｜]\\s*SWR (Handwerkskunst|Craftsmanship)\\s*$"
                ""
                "--embed-metadata"
                "--embed-chapters"
                "--embed-subs"
                "--sub-langs"
                "de.*,en.*"
                "--write-thumbnail"
                "--convert-thumbnails"
                "jpg"
                "--no-write-playlist-metafiles"
                "--no-overwrites"
                "--ignore-errors"
                "--no-progress"
                "-P"
                "home:${library}"
                "-P"
                "temp:${work}/tmp"
                "-o"
                "${template}.%(ext)s"
                "-o"
                "thumbnail:${template}-thumb.%(ext)s"
                "-o"
                "subtitle:${template}.%(ext)s"
                channel
              ]
            } || [ $? -eq 1 ]
          '';
        };

        systemd.timers.handwerkskunst = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "Sat 04:00";
            Persistent = true;
          };
        };
      }
    )
  ];
}
