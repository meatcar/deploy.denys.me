{ config, lib, ... }:
{
  boot.extraModulePackages = with config.boot.kernelPackages; [ wireguard ];
  networking.wireguard.interfaces = {
    wg0 = {
      ips = [ "10.100.0.1/24" ];
      listenPort = 51820;
      privateKeyFile = "/var/secrets/wg_server_private_key";
      peers = import ./wg-clients.nix;
    };
  };

  networking.nat.enable = true;
  networking.nat.externalInterface = "ens3";
  networking.nat.internalInterfaces = [ "wg0" ];
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];

    # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
    extraCommands = ''
      iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o ens3 -j MASQUERADE
    '';
  };
}
