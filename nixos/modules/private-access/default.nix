{ config, lib, ... }:
let
  cfg = config.mine.privateAccess;
in
{
  options.mine.privateAccess = {
    httpHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "HTTPS hosts served only on the NetBird entrypoint.";
    };
    tcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Additional TCP listeners restricted to NetBird ingress.";
    };
    trustedLANInterfaces = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[a-zA-Z0-9_.-]+");
      default = [ ];
      description = "Explicitly trusted LAN interfaces for SMB and WSD. Empty until verified.";
    };
  };

  config.services.openssh.openFirewall = false;
  config.programs.mosh.openFirewall = false;
  config.networking.firewall = {
    interfaces = {
      wt0 = {
        allowedTCPPorts = [
          22
          9443
        ]
        ++ cfg.tcpPorts;
        allowedUDPPortRanges = [
          {
            from = 60000;
            to = 61000;
          }
        ];
      };
      tailscale0 = {
        allowedTCPPorts = [ 22 ];
        allowedUDPPortRanges = [
          {
            from = 60000;
            to = 61000;
          }
        ];
      };
    };
    extraCommands =
      builtins.replaceStrings
        [ "@privateTCPPorts@" "@storageLANRules@" "@discoveryLANRules@" ]
        [
          (lib.concatMapStringsSep "," toString ([ 9443 ] ++ cfg.tcpPorts))
          (lib.concatMapStringsSep "\n" (
            interface: "-A private-storage -i ${interface} -j RETURN"
          ) cfg.trustedLANInterfaces)
          (lib.concatMapStringsSep "\n" (
            interface: "-A private-discovery -i ${interface} -j RETURN"
          ) cfg.trustedLANInterfaces)
        ]
        (builtins.readFile ./firewall.sh);
  };

  config.services.nginx.virtualHosts =
    lib.genAttrs cfg.httpHosts (_: {
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
          ssl = false;
        }
        {
          addr = "[::]";
          port = 80;
          ssl = false;
        }
        {
          addr = "0.0.0.0";
          port = 9443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 9443;
          ssl = true;
        }
      ];
      extraConfig = ''
        if ($ssl_server_name != $host) { return 421; }
      '';
    })
    // {
      private-reject = {
        default = true;
        rejectSSL = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = 9443;
            ssl = true;
          }
          {
            addr = "[::]";
            port = 9443;
            ssl = true;
          }
        ];
        extraConfig = "return 404;";
      };
    };
}
