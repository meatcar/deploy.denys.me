{ config, pkgs, ... }:
{
  networking.wireguard = {
    enable = true;
  };

  networking.wireguard.interfaces.wg1 = {
    ips = [ "10.100.0.4/24" ];
    privateKeyFile = config.age.secrets.wgPrivateKey.path;
    listenPort = 51821;
    peers = [{
      allowedIPs = [ "10.100.0.0/24" ];
      endpoint = "denys.me:51821";
      publicKey = "IGy2mhROyewfr5wFs8cMt4cZP3U+o8mGMC4L+Xmn2Dw=";
      persistentKeepalive = 25;
    }];
  };

  networking.firewall = {
    allowedUDPPorts = [ 51821 ];
  };

}
