{
  nixosModules.pipewire =
    { lib, ... }:
    lib.mkMerge [
      {
        services.pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };
        security.rtkit.enable = true;
      }
      {
        services.pipewire = {
          enable = true;
          extraConfig = {
            pipewire."99-silent-bell.conf" = {
              "context.properties" = {
                "module.x11.bell" = false;
              };
            };
          };
        };
      }
      {
        services.pipewire.wireplumber.extraConfig."10-bluez" = {
          monitor.bluez.properties.bluez5 = {
            codecs = [
              "sbc"
              "sbc_xq"
              "aac"
            ];
            enable-hw-volume = true;
            enable-msbc = true;
            enable-sbc-xq = true;
            hfphsp-backend = "native";
            roles = [
              "a2dp_sink"
              "a2dp_source"
              "bap_sink"
              "bap_source"
              "hfp_ag"
              "hfp_hf"
              "hsp"
              "hsp_ag"
              "hsp_hf"
              "hsp_hs"
            ];
          };
        };
      }
      {
        services.pipewire.enable = true;
      }
    ];
}
