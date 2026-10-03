{
  overlays.sane-airscan =
    _: super:
    let
      devices = super.writeText "airscan-devices.conf" ''
        [devices]
        "HP Laser MFP 135wg" = http://192.168.1.56:8080/eSCL, eSCL
      '';
    in
    {
      sane-airscan = super.sane-airscan.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          cat ${devices} >> $out/etc/sane.d/airscan.conf
        '';
      });
    };

  systems =
    let
      queue = {
        services.printing.enable = true;
        hardware.printers = {
          ensureDefaultPrinter = "hp-laser";
          ensurePrinters = [
            {
              name = "hp-laser";
              description = "HP Laser MFP 135wg";
              deviceUri = "ipp://192.168.1.56:631/ipp/print";
              model = "everywhere";
            }
          ];
        };
      };

      scanner =
        { pkgs, ... }:
        {
          hardware.sane = {
            enable = true;
            extraBackends = [ pkgs.sane-airscan ];
          };
        };
    in
    {
      m1.modules = [
        queue
        scanner
      ];
      x1e.modules = [ queue ];
    };
}
