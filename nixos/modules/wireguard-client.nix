{ config, lib, ... }:
let
  cfg = config.mine.networking.wireguard;
  clientPort = cfg.serverPort;
in
{
  imports = [ ./wireguard.nix ];
  options = {
    mine = {
      networking.wireguard = {
        serverName = lib.mkOption {
          type = lib.types.str;
          description = "The WireGuard server URL/IP";
        };
        serverPublicKey = lib.mkOption {
          type = lib.types.str;
          description = "The WireGuard server public key";
        };
      };
    };
  };
  config = {
    networking.wireguard = {
      enable = true;
      interfaces.wg1 = {
        ips = [ "10.100.0.${toString cfg.ipIndex}/24" ];
        privateKeyFile = config.age.secrets.wgPrivateKey.path;
        listenPort = clientPort;
        peers = [{
          allowedIPs = [ "10.100.0.0/24" ];
          endpoint = "${cfg.serverName}:${toString cfg.serverPort}";
          publicKey = cfg.serverPublicKey;
          persistentKeepalive = 25;
        }];
      };

    };

    networking.firewall = {
      allowedUDPPorts = [ clientPort ];
    };
  };
}
