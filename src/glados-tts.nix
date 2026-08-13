{ sources, system, ... }:
{
  overlays.glados-tts = self: super: {
    # nixpkgs-22.05's pytorch (1.11) is built without FBGEMM, so on this
    # non-mobile CPU build torch's default quantized engine is `none`.
    # glados.pt is a quantized TorchScript model, and torch.jit.load() rejects
    # it under `none` with `RuntimeError: Unknown qengine`; select the first
    # backend the build actually supports (qnnpack here) before any load.
    #
    # The packaged `glados` (glados.py) also plays audio itself via `aplay`
    # (not in glados-announce's PATH) and writes nothing to stdout; rewrite it
    # to emit a WAV stream on stdout instead, so `glados | mpv` can play it.
    glados-tts =
      (import sources.glados-tts {
        pkgs = import sources.nixpkgs-22_05 { inherit system; };
      }).glados.overrideAttrs
        (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace glados.py \
              --replace 'import torch' \
                'import torch; torch.backends.quantized.engine = next((e for e in torch.backends.quantized.supported_engines if e != "none"), "none")' \
              --replace 'p = Popen(["aplay", "-f", "S16_LE", "-r", "22050", "-"], stdin=PIPE, stdout=DEVNULL, stderr=DEVNULL)' \
                'write(sys.stdout.buffer, 22050, audio)' \
              --replace 'p.communicate(input=audio.tobytes())' \
                'pass'
          '';
        });
  };
  systems.tower.modules = [
    (
      # NixOS module: hourly time/date/weather announcement in the voice of GLaDOS.
      #
      # It is a *user* service+timer on purpose: playing audio needs access to the
      # logged-in user's sound server (PipeWire/PulseAudio), which user units get for
      # free. Enable it per user with `systemctl --user enable --now glados-hourly.timer`
      { lib, pkgs, ... }:

      let
        # Leave empty to let wttr.in geolocate tower by its public IP, or pin a place,
        # e.g. "Berlin", "Hamburg", or a "lat,lon" pair like "53.55,9.99".
        location = "";

        glados-announce = pkgs.writeShellApplication {
          name = "glados-announce";
          runtimeInputs = with pkgs; [
            glados-tts
            ffmpeg
            curl
            mpv
            coreutils
          ];
          text = ''
            when="$(date '+It is %-I %p on %A, %B %-d')"

            # wttr.in emits weather units (°C, hPa, ...) that glados-tts' cleaner knows
            # how to speak. Degrade gracefully if the network or wttr.in is down.
            if weather="$(curl -fsS --max-time 15 'wttr.in/${location}?format=%C+%t')"; then
              report="$when. The weather is $weather."
            else
              report="$when. Weather data is currently unavailable."
            fi

            # glados reads one line of text on stdin and writes a WAV stream to stdout;
            # mpv plays it through the user's sound server ('-' tells mpv to read stdin).
            printf '%s\n' "$report" | glados | mpv --no-video --really-quiet -
          '';
        };
      in
      {
        # glados-tts is desktop-only (needs audio + the tower CPU build of the
        # 22.05 pytorch, which is marked broken on aarch64); keep it off other
        # hosts so m1 etc. don't drag it in.
        environment.systemPackages = [ pkgs.glados-tts ];
        systemd.user.services.glados-hourly = {
          description = "Announce the hour, date and weather in the voice of GLaDOS";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe glados-announce;
          };
        };

        systemd.user.timers.glados-hourly = {
          description = "Hourly GLaDOS time, date and weather announcement";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            AccuracySec = "1s";
            Persistent = false;
          };
        };
      }
    )
  ];
}
