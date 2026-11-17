{
  # Home Assistant voice (Assist) with m1 as the microphone and speaker.
  #
  # m1 runs a Wyoming satellite: its microphone goes to openWakeWord on tower,
  # and after the wake word to Home Assistant, which runs speech-to-text
  # (faster-whisper), the command, and text-to-speech (Piper), and sends the
  # answer back for m1 to play. openWakeWord cannot run on m1 itself: nixpkgs
  # marks pyopen-wakeword broken on aarch64-linux (its bundled TensorFlow Lite
  # segfaults), so m1 streams its microphone to tower continuously -- over the
  # babel mesh only (see the firewall rules below).
  #
  # Home Assistant has no YAML for Wyoming, so the wiring is done once in its
  # UI. After deploy, under Settings -> Devices & services -> Add integration
  # -> Wyoming Protocol, add
  #   * 127.0.0.1 port 10300 (faster-whisper) and 127.0.0.1 port 10200 (Piper),
  #   * m1 port 10700 (the satellite);
  # then under Settings -> Voice assistants make (or edit) a German pipeline
  # with faster-whisper and Piper, and select it on the m1 satellite device.
  systems.tower.modules = [
    (
      { pkgs, ... }:
      {
        # Only Home Assistant (on the same host) connects, so both stay on
        # localhost, without zeroconf announcements.
        services.wyoming.faster-whisper.servers.de = {
          enable = true;
          uri = "tcp://127.0.0.1:10300";
          zeroconf.enable = false;
          language = "de";
          sttLibrary = "faster-whisper";
          # On the Quadro T400 (4 GB, Turing): large-v3-turbo takes about
          # 1.6 GB, leaving room for Jellyfin's NVENC sessions.
          device = "cuda";
          model = "turbo";
        };
        # CUDA for CTranslate2 only: nixpkgs-wide cudaSupport would also rebuild
        # onnxruntime and others. The module grants the unit the NVIDIA devices
        # for device = "cuda".
        services.wyoming.faster-whisper.package = pkgs.wyoming-faster-whisper.override {
          python3Packages = pkgs.python3Packages.overrideScope (
            _: super: {
              ctranslate2 = super.ctranslate2.override {
                ctranslate2-cpp = pkgs.ctranslate2.override {
                  withCUDA = true;
                  withCuDNN = true;
                };
              };
            }
          );
        };
        # Compile CUDA code for the T400 alone, not every GPU generation.
        nixpkgs.config.cudaCapabilities = [ "7.5" ];
        # The CUDA libraries CTranslate2 builds against (CUDA EULA).
        unfree.packages = [
          "cccl"
          "cuda_cudart"
          "cuda_nvcc"
          "libnvvm"
          "cuda_crt"
          "libcublas"
          "cuda_nvrtc"
          "libcurand"
          "cudnn"
        ];
        services.wyoming.piper.servers.de = {
          enable = true;
          uri = "tcp://127.0.0.1:10200";
          zeroconf.enable = false;
          voice = "de_DE-thorsten-medium";
        };
        services.home-assistant.extraComponents = [ "wyoming" ];

        # For m1's satellite (see above), over the mesh.
        services.wyoming.openwakeword = {
          enable = true;
          uri = "tcp://[::]:10400";
        };
        networking.firewall.extraInputRules = ''
          ip6 saddr fd42:1234:5678:90ab::/64 tcp dport 10400 accept
        '';

        # Both download their models into their StateDirectory. They are
        # DynamicUser services, so it lives under /var/lib/private (see
        # CLAUDE.md, Persistence).
        state.directories = [
          "/var/lib/private/wyoming/faster-whisper"
          "/var/lib/private/wyoming/piper"
        ];
      }
    )
  ];

  systems.m1.modules = [
    {
      services.wyoming.satellite = {
        enable = true;
        # Runs as the desktop user, to record and play through its PipeWire
        # session (the module points XDG_RUNTIME_DIR there; arecord/aplay go
        # through PipeWire's ALSA plugin).
        user = "aforemny";
        # Home Assistant on tower connects to this. [::] so it is reachable
        # over the babel mesh, which is IPv6 (tower resolves m1 to its ULA).
        uri = "tcp://[::]:10700";
        extraArgs = [
          "--wake-uri"
          "tcp://tower:10400"
          "--wake-word-name"
          "ok_nabu"
        ];
      };

      # Reachable only over the babeld overlay (see babeld.nix, iperf3.nix):
      # the satellite streams the microphone to whoever connects.
      networking.firewall.extraInputRules = ''
        ip6 saddr fd42:1234:5678:90ab::/64 tcp dport 10700 accept
      '';
    }
  ];
}
