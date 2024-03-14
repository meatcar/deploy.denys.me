{
  config,
  lib,
  ...
}: let
  cfg = config.mine.nginx-sni-proxy;
in {
  options.mine.nginx-sni-proxy = {
    enable = lib.mkEnableOption "nginx-sni-proxy";
    proxies = lib.mkOption {
      description = "Domain names to proxy using ngx_stream_ssl_preread_module";
      default = [];
      type = lib.types.attrsOf (lib.types.submodule {
        options.subdomains = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to route all subdomains";
        };
        options.host = lib.mkOption {
          type = lib.types.str;
          description = "Which host to route all matched traffic to";
        };
      });
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [443];
    services.nginx = let
      defaultSSLListenPort = config.services.nginx.defaultSSLListenPort;
      upstreams = lib.pipe cfg.proxies [
        (lib.concatMapAttrs (
          name: opts:
            {${name} = opts.host;}
            // (lib.optionalAttrs opts.subdomains {"~.+.${name}" = opts.host;})
        ))
        (lib.mapAttrsToList (name: host: "${name} ${host}:443;"))
        lib.concatLines
      ];
    in {
      defaultSSLListenPort = lib.mkDefault 44443;
      streamConfig = ''
        map $ssl_preread_server_name $sni_proxy {
          ${upstreams}
          default 127.0.0.1:${toString defaultSSLListenPort};
        }
        server {
          listen 443;
          ssl_preread on;
          resolver 1.1.1.1;
          proxy_pass $sni_proxy;
        }
      '';
      virtualHosts =
        builtins.mapAttrs
        (name: opts: {
          locations."/".proxyPass = "http://${opts.host}";
          serverAliases = lib.mkIf opts.subdomains ["*.${name}"];
        })
        cfg.proxies;
    };
  };
}
