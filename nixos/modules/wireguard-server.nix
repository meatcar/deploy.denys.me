{ config, pkgs, lib, ... }:
let
  external = config.networking.nat.externalInterface;
  wgInterface = "wg1";
  serverPort = config.mine.networking.wireguard.serverPort;
in
{
  imports = [ ./wireguard.nix ];
  config = {
    networking.nat.enable = true;
    # networking.nat.externalInterface is configured elsewhere per-host
    networking.nat.internalInterfaces = [ wgInterface ];
    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 serverPort ];
    };

    networking.wireguard.interfaces.${wgInterface } = {
      ips = [ "10.100.0.1/24" ];
      listenPort = serverPort;
      privateKeyFile = config.age.secrets.wg-priv-key.path;
      peers = import ../generated/wg-clients.nix;

      # TODO: I think networking.nat does the same thing as below. Keeping just incase.
      # postSetup = ''
      #   ${pkgs.iptables}/bin/iptables -A FORWARD -i ${wgInterface } -j ACCEPT
      #   ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o ${external} -j MASQUERADE
      # '';
      #
      # # This undoes the above command
      # postShutdown = ''
      #   ${pkgs.iptables}/bin/iptables -D FORWARD -i ${wgInterface } -j ACCEPT
      #   ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o ${external} -j MASQUERADE
      # '';
    };
  };
}
