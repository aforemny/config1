{
  # AirPlay mirroring/video target: iPhones and iPads list m1 under Screen
  # Mirroring, and AirPlay video from apps plays in a window on its desktop.
  systems.m1.modules = [
    (
      { lib, pkgs, ... }:
      let
        # UxPlay's legacy fixed ports (`-p`); unpinned it picks random ones,
        # which the firewall cannot allow ahead of time.
        tcpPorts = [
          7000
          7001
          7100
        ];
        udpPorts = [
          6000
          6001
          7011
        ];
        ports = l: lib.concatMapStringsSep ", " toString l;
      in
      {
        # systemd-resolved also answers mDNS (on wlan0 by default) and claims
        # m1.local, so avahi saw a conflict on every start and renamed itself
        # m1-2 ... m1-6.local; the iPhone then could not resolve the service.
        # Leave mDNS to avahi alone.
        services.resolved.settings.Resolve.MulticastDNS = false;

        # UxPlay announces _airplay._tcp/_raop._tcp through avahi's dns_sd
        # compat library, i.e. as a user service.
        services.avahi = {
          enable = true;
          openFirewall = true;
          settings.publish = {
            disable-publishing = false;
            disable-user-service-publishing = false;
            publish-addresses = true;
          };
        };

        # Only from the home LAN (and link-local, which AirPlay over IPv6
        # uses), not from whatever network the laptop happens to be on.
        networking.firewall.extraInputRules = ''
          ip saddr 192.168.1.0/24 tcp dport { ${ports tcpPorts} } accept
          ip saddr 192.168.1.0/24 udp dport { ${ports udpPorts} } accept
          ip6 saddr fe80::/10 tcp dport { ${ports tcpPorts} } accept
          ip6 saddr fe80::/10 udp dport { ${ports udpPorts} } accept
        '';

        environment.systemPackages = [ pkgs.uxplay ];

        # Runs in the desktop session, so it can open a Wayland window and
        # play through PipeWire.
        systemd.user.services.uxplay = {
          description = "AirPlay mirroring server";
          partOf = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            # -hls: accept the YouTube app's handed-off (HLS) video, which m1
            # then streams itself; without it YouTube falls back to mirroring.
            #
            # -fs: full screen, for mirroring and handed-off video alike.
            #
            # stdbuf -oL: UxPlay logs to stdout, which glibc fully buffers when
            # it is not a terminal, so the journal got its lines in delayed
            # bursts (or not at all for a quiet session).
            ExecStart = "${pkgs.coreutils}/bin/stdbuf -oL -eL ${lib.getExe pkgs.uxplay} -n m1 -nh -p -hls -fs";
            Restart = "on-failure";
          };
        };
      }
    )
  ];
}
