{
  systems.family.modules = [
    (
      { lib, pkgs, ... }:
      {
        networking = {
          hostId = "30d27915";
          domain = "apostolforemny.de";
          networkmanager.enable = false;
        };
        tags.graphical = false;

        # Hetzner Cloud routes 2a01:4f8:1c1b:e9e6::/64 to this VM, but hands out
        # neither DHCPv6 nor an RA prefix -- only the router at the well-known
        # link-local fe80::1 -- so address and default route are static.  Without
        # a matching .network the stock 99-ethernet-default-dhcp.network wins and
        # the machine is IPv4-only.
        systemd.network.networks."40-enp1s0" = {
          matchConfig.Name = "enp1s0";
          address = [ "2a01:4f8:1c1b:e9e6::1/64" ];
          routes = [ { Gateway = "fe80::1"; } ];
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            IPv6PrivacyExtensions = "kernel";
          };
          linkConfig.RequiredForOnline = "routable";
        };

        localAccounts = {
          aforemny.passwordFile = pkgs.asecret-lib.password "per-user/aforemny/apostolforemny.de/aforemny/password";
          shared.passwordFile = pkgs.asecret-lib.password "per-host/family/per-user/shared/password";
        };

        services.babeld.enable = lib.mkForce false;
        services.syncoid.enable = lib.mkForce false;
      }
    )
  ];
}
