_: {
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    statusPage = true;
    virtualHosts.public-reject = {
      default = true;
      rejectSSL = true;
      extraConfig = "return 404;";
    };
  };
}
