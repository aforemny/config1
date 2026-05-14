{
  platforms.m1 =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        disko.devices = {
          disk = {
            main = {
              type = "disk";
              device = "/dev/disk/by-id/nvme-APPLE_SSD_AP0256Q_0ba01463c4dd4433_1";
              destroy = false; # TODO
              content = {
                type = "gpt";
                partitions = {
                  iBootSystemContainer = {
                    label = "iBootSystemContainer";
                    priority = 1;
                    type = "AF0B";
                    uuid = "9b208117-ca48-4c66-97cc-316bdc17d91f";
                    start = 6;
                    end = 128005;
                  };
                  Container = {
                    label = "Container";
                    priority = 2;
                    type = "AF0A";
                    uuid = "616feeb0-5d98-4947-8257-882cea1787da";
                    start = 128006;
                    end = 14536453;
                  };
                  NixOSContainer = {
                    priority = 3;
                    type = "AF0A";
                    uuid = "29198fa3-3044-40e6-bfc8-5f4e51db64e4";
                    start = 14536454;
                    end = 15146757;
                  };
                  ESP = {
                    priority = 4;
                    type = "EF00";
                    uuid = "eab932c7-700e-4dd2-bd74-65796f693a98";
                    start = 15146758;
                    end = 15268869;
                    content = {
                      type = "filesystem";
                      format = "vfat";
                      mountpoint = "/boot";
                      mountOptions = [
                        "rw"
                        "relatime"
                        "fmask=0022"
                        "dmask=0022"
                        "codepage=437"
                        "iocharset=ascii"
                        "shortname=mixed"
                        "errors=remount-ro"
                      ];
                    };
                  };
                  root = {
                    priority = 5;
                    type = "8300";
                    uuid = "6e40af2b-9bec-4703-a5e2-c2c11f190275";
                    start = 15268870;
                    end = 59968629;
                    content = {
                      type = "filesystem";
                      format = "ext4";
                      mountpoint = "/";
                    };
                  };
                  RecoveryOSContainer = {
                    label = "RecoveryOSContainer";
                    priority = 6;
                    type = "AF0C";
                    uuid = "813c5213-2c63-42e0-b4ab-644d5a9cd277";
                    start = 59968630;
                    end = 61279338;
                  };
                };
              };
            };
          };
        };
      }
      {
        hardware = {
          asahi.enable = true;
          facter = {
            enable = true;
            reportPath = ./m1.json;
          };
        };
      }
      {
        boot.loader = {
          efi.canTouchEfiVariables = false;
          systemd-boot.enable = true;
        };
        hardware = {
          asahi.extractPeripheralFirmware = false; # TODO
          asahi.setupAsahiSound = true;
          graphics.enable = true;
        };
        networking.wireless.iwd.enable = true;
        services.libinput.enable = true;
        system.stateVersion = "23.11";
      }
    ];
}
