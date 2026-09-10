{ sources, ... }:
{
  systems.tower.modules = [
    "${sources.declarative-runtime}/services/jellyfin/module.nix"
    (
      { pkgs, ... }:
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

            # Offload transcoding to Quick Sync. Measured on tower against the
            # live library (1080p H.264 -> 720p, while the box was already
            # loaded): libx264 veryfast managed 3.15x realtime at ~635% CPU,
            # h264_vaapi 13.9x at ~46% of a single core. The software path is
            # what drives the package to TjMax (105 C) and throttles all cores
            # to 1.7 GHz, so this is a thermal fix as much as a speed one.
            #
            # Decode is offloaded only for the formats vainfo reports on this
            # GPU (H.264/VC1/MPEG-2 VLD). Ivy Bridge has no fixed-function
            # block for HEVC, VP9 or AV1, so those keep decoding in software
            # and only their encode leg is accelerated. HEVC/AV1 *encode*
            # stays off for the same reason.
            # (EnableIntelLowPower*HwEncoder likewise stay false: VDEnc is
            # Skylake and newer.)
            #
            # The provider string-compares the planned `configuration_json`
            # against what it reads back after applying, and the server answers
            # with its *whole* merged EncodingOptions -- a partial object makes
            # the apply land but then fail the unit with "Provider produced
            # inconsistent result after apply". So every key the provider
            # returns is spelled out here; only the three below are the actual
            # change. (Same reasoning as the full branding.xml render in
            # src/jellyfin-ldap.nix: state the whole document, not a delta.)
            #   HardwareAccelerationType, HardwareDecodingCodecs, VaapiDevice
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
              EnableTonemapping = false;
              EnableVideoToolboxTonemapping = false;
              EnableVppTonemapping = false;
              EncodingThreadCount = -1;
              H264Crf = 23;
              H265Crf = 28;
              HardwareAccelerationType = "vaapi";
              HardwareDecodingCodecs = [
                "h264"
                "vc1"
                "mpeg2video"
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

        # Userspace VA driver for the i7-3770's HD Graphics 4000 (8086:0162).
        # tower is headless (tags.graphical = false), so nothing else pulls a
        # DRI driver in: without this the kernel's render node exists but
        # /run/opengl-driver/lib/dri is empty and vaInitialize() fails with -1,
        # which is why Jellyfin had HardwareAccelerationType=none.
        hardware.graphics = {
          enable = true;
          extraPackages = [ pkgs.intel-vaapi-driver ];
        };

        # libva probes iHD first for i915 and falls back to i965 on its own, so
        # this is not strictly required today -- it is pinned because iHD only
        # supports Broadwell and newer: should anything ever add
        # intel-media-driver to extraPackages, the probe would succeed and
        # silently break transcoding on this pre-Broadwell GPU.
        systemd.services.jellyfin.environment.LIBVA_DRIVER_NAME = "i965";

        # No render/video group membership here on purpose: PrivateUsers=true
        # maps only the unit's own user+group (see the `group` note above), so
        # a supplementary group would not survive into the namespace anyway.
        # systemd's own udev rules give /dev/dri/renderD128 mode 0666 and the
        # unit sets PrivateDevices=false, so the render node is already
        # reachable as the jellyfin user.

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
