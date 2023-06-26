{ config, pkgs, lib, ... }:
{
  networking.nat.enable = true;
  networking.nat.externalInterface = "ens3";
  networking.nat.internalInterfaces = [ "wg1" ];
  networking.firewall = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 51821 ];
  };

  networking.wireguard.enable = true;
  networking.wireguard.interfaces.wg1 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51821;
    privateKeyFile = config.age.secrets.wg-priv-key.path;
    peers = import ../generated/wg-clients.nix;

    postSetup = ''
      ${pkgs.iptables}/bin/iptables -A FORWARD -i wg1 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o eth0 -j MASQUERADE
    '';

    # This undoes the above command
    postShutdown = ''
      ${pkgs.iptables}/bin/iptables -D FORWARD -i wg1 -j ACCEPT
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o eth0 -j MASQUERADE
    '';
  };
}
