{
  nixosModules.iperf3 = { pkgs, ... }: {
    services.iperf3 = {
      enable = true;
      openFirewall = true;
    };
    environment.systemPackages = with pkgs; [ iperf3 ];
  };
}
