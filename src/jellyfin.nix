{ sources, ... }:
{
  systems.tower.modules = [
    "${sources.declarative-runtime}/services/jellyfin/module.nix"
    (
      let
        fqdn = "j.nomath.org";
        port = 8096;
      in
      {
        services.jellyfin = {
          enable = true;
          # Share the media stack's primary group so Jellyfin can read the
          # library that Sonarr/Radarr populate on /srv/media (see
          # src/servarr.nix). PrivateUsers=true on jellyfin.service maps only
          # the unit's own user+group, so this must be the PRIMARY group, not a
          # supplementary one. Jellyfin's own state is 0700 (UMask 0077), so
          # the group carries no extra access to it.
          group = "transmission";

          runtime = {
            enable = true;
            libraries.movies = {
              collection_type = "movies";
              paths = [ "/srv/media/library/movies" ];
            };
            libraries.shows = {
              collection_type = "tvshows";
              paths = [ "/srv/media/library/tv" ];
            };

            # Transcode on the Quadro T400 (TU117), not the CPU: the software
            # path drives the i7-3770 to TjMax and throttles every core. This
            # has to be stated: Jellyfin's own default is no acceleration at
            # all, and it does not detect the card by itself.
            #
            # Decode is offloaded for what NVDEC has on Turing; AV1 is not on
            # that list and keeps decoding in software. Tonemapping is on so
            # HDR sources stay watchable on SDR clients.
            #
            # The provider string-compares the planned `configuration_json`
            # against what it reads back after applying, and the server answers
            # with its *whole* merged EncodingOptions -- a partial object makes
            # the apply land but then fail the unit with "Provider produced
            # inconsistent result after apply". So every key the provider
            # returns is spelled out here; only the three below are the actual
            # change. (Same reasoning as the full branding.xml render in
            # src/jellyfin-ldap.nix: state the whole document, not a delta.)
            #   HardwareAccelerationType, HardwareDecodingCodecs, EnableTonemapping
            encoding_configuration.default.configuration_json = builtins.toJSON {
              AllowAv1Encoding = false;
              AllowHevcEncoding = false;
              AllowOnDemandMetadataBasedKeyframeExtractionForExtensions = [
                "mkv"
              ];
              DeinterlaceDoubleRate = false;
              DeinterlaceMethod = "yadif";
              DownMixAudioBoost = 2;
              DownMixStereoAlgorithm = "None";
              EnableAudioVbr = false;
              EnableDecodingColorDepth10Hevc = true;
              EnableDecodingColorDepth10HevcRext = false;
              EnableDecodingColorDepth10Vp9 = true;
              EnableDecodingColorDepth12HevcRext = false;
              EnableEnhancedNvdecDecoder = true;
              EnableFallbackFont = false;
              EnableHardwareEncoding = true;
              EnableIntelLowPowerH264HwEncoder = false;
              EnableIntelLowPowerHevcHwEncoder = false;
              EnableSegmentDeletion = false;
              EnableSubtitleExtraction = true;
              EnableThrottling = false;
              EnableTonemapping = true;
              EnableVideoToolboxTonemapping = false;
              EnableVppTonemapping = false;
              EncodingThreadCount = -1;
              H264Crf = 23;
              H265Crf = 28;
              HardwareAccelerationType = "nvenc";
              HardwareDecodingCodecs = [
                "h264"
                "hevc"
                "mpeg2video"
                "vc1"
                "vp8"
                "vp9"
              ];
              MaxMuxingQueueSize = 2048;
              PreferSystemNativeHwDecoder = true;
              QsvDevice = "";
              SegmentKeepSeconds = 720;
              ThrottleDelaySeconds = 180;
              TonemappingAlgorithm = "bt2390";
              TonemappingDesat = 0;
              TonemappingMode = "auto";
              TonemappingParam = 0;
              TonemappingPeak = 100;
              TonemappingRange = "auto";
              VaapiDevice = "/dev/dri/renderD128";
              VppTonemappingBrightness = 16;
              VppTonemappingContrast = 1;
            };
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
              extraConfig = ''
                proxy_buffering off; # don't buffer media streams
                client_max_body_size 20M; # subtitle / plugin uploads
              '';
            };
          };
        };

        networking.firewall.allowedTCPPorts = [
          80
          443
        ];

        dns.dynamicAAAA = [ "j" ];

        # /var/lib/jellyfin is created by the module via tmpfiles, not
        # StateDirectory=, so under impermanence its bind-mount root defaults to
        # root:root and Jellyfin cannot create its dataDir. Persist it with
        # explicit ownership so impermanence creates the /persist source owned
        # by the service (group 'transmission' to match services.jellyfin.group).
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/jellyfin";
            user = "jellyfin";
            group = "transmission";
            mode = "0700";
          }
        ];

        state.directories = [
          # Mint-once admin password for the runtime reconciler. Its unit uses
          # StateDirectory= (systemd chowns the bind mount at start), so a bare
          # string is fine. Losing it to the rootfs rollback would strand the
          # reconciler's credential for the admin it already created.
          "/var/lib/declarative-jellyfin-password"
          "/var/lib/acme"
        ];
      }
    )
  ];
}
