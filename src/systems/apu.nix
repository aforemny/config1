{ sources, ... }:
{
  systems.apu.modules = [
    (
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        config = lib.mkMerge [
          {
            hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
            hardware.enableRedistributableFirmware = true;
            #hardware.enableAllFirmware = true;
            nixpkgs.config.allowUnfree = true;
            networking.networkmanager.enable = false;
          }
          ({
            services.hostapd = {
              enable = true;
              radios.wlp5s0 = {
                networks.wlp5s0 = {
                  ssid = "apu";
                  #authentication.saePasswords = [
                  #  {
                  #    password = "my_sekret";
                  #  }
                  #];
                  authentication = {
                    mode = "wpa3-sae-transition";
                    saePasswords = [ { password = "my_sekret"; } ];
                    wpaPassword = "my_sekret";
                  };
                };
              };
            };
            environment.systemPackages = with pkgs; [
              btop
              iw
              nixos-facter
              pciutils
              speedtest-cli
              tcpdump
              usbutils
            ];
            networking.interfaces.wlp5s0.ipv4.addresses = [
              {
                address = "192.168.1.1";
                prefixLength = 24;
              }
            ];

            networking.nat = {
              enable = true;
              enableIPv6 = true;
              externalInterface = "ppp0";
              internalInterfaces = [ "wlp5s0" ];
            };

            services.dnsmasq = {
              enable = true;
              settings = {
                bind-interfaces = true;
                interface = "wlp5s0";
                dhcp-range = [
                  "192.168.1.2,192.168.1.254"
                  "::1,::400,constructor:wlp5s0,ra-names,12h"
                ];
                dhcp-option = [
                  "option6:dns-server,[::]"
                ];
                enable-ra = true;
                server = [
                  "8.8.8.8"
                  "8.8.4.4"
                ];
                domain-needed = true;
                bogus-priv = true;
              };
            };
            systemd.services.dnsmasq = {
              after = [ "sys-subsystem-net-devices-wlp5s0.device" ];
              requires = [ "sys-subsystem-net-devices-wlp5s0.device" ];
            };

            services.resolved.enable = false;
            networking.nameservers = [ "127.0.0.1" ];

            systemd.network.networks."40-ppp0" = {
              matchConfig.Name = "ppp0";
              networkConfig = {
                DHCP = "ipv6";
                DefaultRouteOnDevice = true;
                KeepConfiguration = "static";
              };
              dhcpV6Config = {
                PrefixDelegationHint = "::/56";
                WithoutRA = "solicit";
                UseAddress = false;
                UseDNS = false;
                UseNTP = false;
                UseHostname = false;
                UseDomains = false;
              };
            };
            systemd.network.networks."40-wlp5s0" = {
              matchConfig.Name = "wlp5s0";
              networkConfig = {
                DHCPPrefixDelegation = "yes";
                IPv6SendRA = true;
              };
            };

            networking.firewall.allowedUDPPorts = [
              53
              67
              953
            ];
            networking.firewall.allowedTCPPorts = [
              53
              67
              953
            ];
            #services.dhcpd4.enable = true;
            #services.dhcpd4.interfaces = [ "wlp5s0" ];
            #services.dhcpd4.extraConfig = ''
            #  option subnet-mask 255.255.255.0;
            #  option broadcast-address 192.168.1.255;
            #  option routers 192.168.1.1;
            #  option domain-name-servers 192.168.1.1;

            #  subnet 192.168.1.0 netmask 255.255.255.0 {
            #    range 192.168.1.100 192.168.1.199;
            #  }
            #'';

            #services.bind.enable = true;
            #services.bind.cacheNetworks = [
            #  "127.0.0.0/24"
            #  "192.168.1.0/24"
            #  "10.1.1.0/24"
            #];
            #services.bind.extraOptions = ''
            #  allow-recursion { cachenetworks; };
            #'';
            #services.bind.zones."apu" = {
            #  master = true;
            #  file = pkgs.writeTextFile {
            #    name = "apu.zone";
            #    text = ''
            #      $TTL 2h
            #      @          IN SOA ns1 hostmaster (
            #                          1
            #                          8h
            #                          30m
            #                          1w
            #                          1h )
            #      @          IN NS  apu.
            #      @          IN A   192.168.1.1
            #      cgit       IN A   192.168.1.1
            #      hass       IN A   192.168.1.1
            #      radicale   IN A   192.168.1.1
            #      news       IN A   192.168.1.110
            #    '';
            #  };
            #};
            #networking.nameservers = [ "8.8.8.8" ];
          })
          (
            # pppd
            let
              username = "1und1/ui6870-442@online.de";
              password = "7V9RRzam@";
            in
            {
              services.pppd = {
                enable = true;
                peers."1und1" = {
                  autostart = true;
                  enable = true;
                  config = ''
                    plugin pppoe.so wan

                    nic-wan
                    # pppd supports multiple ways of entering credentials,
                    # this is just 1 way
                    name "${username}"
                    password "${password}"

                    persist
                    nodetach
                    maxfail 0
                    holdoff 5

                    noipdefault
                    defaultroute
                    replacedefaultroute

                    hide-password
                    lcp-echo-interval 20
                    lcp-echo-failure 3
                    noauth
                  '';
                };
              };
              systemd.services.pppd-1und1.unitConfig.StartLimitIntervalSec = 0;
              networking = {
                vlans.wan = {
                  id = 7;
                  interface = "enp4s0";
                };
                # bring up interface
                interfaces.wan = {
                  useDHCP = false;
                  ipv4.addresses = [ ];
                };
              };
              networking.interfaces.enp4s0.useDHCP = false;
              systemd.tmpfiles.rules = [
                "f /etc/ppp/chap-secrets 0600 root root -"
              ];
              fileSystems."/etc/ppp/chap-secrets" = {
                device = pkgs.asecret-lib.password "isp/1und1/password";
                fsType = "auto";
                options = [
                  "bind"
                  "ro"
                ];
              };
            }
          )
          {
            networking.hostId = "c05410b7";
            networking.hostName = "apu";
            system.stateVersion = "25.11";
            boot.loader = {
              grub.enable = true;
              systemd-boot.enable = false;
            };
            # nixos-hardware
            boot.kernelParams = [ "console=ttyS0,115200n8" ];
            boot.loader.grub.extraConfig = ''
              serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
              terminal_input serial
              terminal_output serial
            '';
          }
        ];
      }
    )
  ];
}
