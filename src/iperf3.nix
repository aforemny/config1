{
  nixosModules.iperf3 = {
    services.iperf3 = {
      enable = true;
      openFirewall = true;
    };
  };
}
