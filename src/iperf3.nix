{
  nixosModules.iperf3 =
    { pkgs, ... }:
    {
      services.iperf3 = {
        enable = true;
        openFirewall = false;
      };
      # Reachable only over the babeld overlay (ULA fd42:1234:5678:90ab::/64,
      # see babeld.nix), never from the public internet. `openFirewall` would
      # publish the unauthenticated TCP 5201 server on every interface.
      networking.firewall.extraInputRules = ''
        ip6 saddr fd42:1234:5678:90ab::/64 tcp dport 5201 accept
      '';
      environment.systemPackages = with pkgs; [ iperf3 ];
    };
}
