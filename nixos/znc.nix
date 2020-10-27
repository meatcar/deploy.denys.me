{ config, pkgs, lib, ... }:
let cfg = config.mine.znc;
in
{
  options.mine.znc =
    let
      inherit (lib) mkOption types;
    in
    {
      port = mkOption {
        type = types.int;
        description = "Port to expose IRC on";
        default = 7000;
      };
      users = mkOption {
        description = "znc users";
        type = types.attrsOf (types.submodule {
          options = {
            password = mkOption {
              type = types.str;
              description = "Password to encrypt user's files with";
            };
            hash = mkOption {
              type = types.str;
              description = "ZNC Password hash";
            };
            salt = mkOption {
              type = types.str;
              description = "ZNC Password salt";
            };
            extraConfig = mkOption {
              type = types.attrs;
              description = "ZNC User extra configuration";
            };
            networks = mkOption {
              description = "Users' networks";
              type = types.attrsOf (types.submodule {
                options = {
                  nickservPassword = mkOption {
                    description = "Network's nickserv password";
                    type = types.str;
                  };
                  extraConfig = mkOption {
                    type = types.attrs;
                    description = "Network's extra configuration";
                  };
                };
              });
            };
          };
        });
      };
    };

  config = {

    system.activationScripts =
      let
        inherit (lib) pipe mapAttrsToList concatStringsSep stringAfter;
      in
      {
        znc-sasl2 = pipe cfg.users [
          (mapAttrsToList (username: user-config:
            pipe user-config.networks [
              (mapAttrsToList (servername:
                { nickservPassword, ... }: ''
                  ZNC_SASL_MODDATA=/var/lib/znc/users/${username}/networks/${servername}/moddata/sasl
                  mkdir -p $ZNC_SASL_MODDATA
                  echo $'password ${nickservPassword}\nusername ${username}' > $ZNC_SASL_MODDATA/.registry''))
              (concatStringsSep "\n")
            ]
          ))
          (concatStringsSep "\n")
          (stringAfter [ "etc" ])
        ];
      };

    services.znc =
      let
        makeUserNetworks = { password, networks, ... }:
          lib.mapAttrs
            (servername: server-config:
              {
                LoadModule = [
                  "nickserv"
                  "chansaver"
                  "simple_away"
                  "savebuff ${password}"
                  "awaystore -notimer ${password}"
                  "stickychan"
                  "keepnick"
                  "sasl"
                ];
              } // server-config.extraConfig
            )
            networks;
        makeUser = username: user-config:
          {
            Admin = lib.mkDefault false;
            Nick = lib.mkDefault "${username}";
            AltNick = lib.mkDefault "${username}_";
            QuitMsg = lib.mkDefault "bye bye.";
            LoadModule =
              [ "chansaver" "controlpanel" "log" "notes" "autoreply" "alias" ];

            Pass.password = {
              Method = "sha256";
              Hash = user-config.hash;
              Salt = user-config.salt;
            };
            Network = makeUserNetworks user-config;
          } // user-config.extraConfig;
      in
      {
        enable = true;
        mutable = false;
        useLegacyConfig = false;
        openFirewall = false;
        modulePackages = [ pkgs.zncModules.push pkgs.zncModules.backlog ];
        config = {
          LoadModule = [ "webadmin" "backlog" ];
          TrustedProxy = [ "127.0.0.1" "::1" ];
          Listener.l = {
            AllowIRC = true;
            AllowWeb = true;
            Port = 6697;
            SSL = false;
          };
          User = lib.mapAttrs makeUser cfg.users;
        };
      };

    services.nginx =
      let
        domain = "znc.${config.mine.domain}";
        upstream =
          "localhost:${toString config.services.znc.config.Listener.l.Port}";
      in
      {
        virtualHosts."${domain}" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            proxyPass = "http://${upstream}";
            extraConfig = ''
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            '';
          };
        };
        appendStreamConfig = ''
          upstream znc-irc {
            server ${upstream};
          }
          server {
            listen ${toString cfg.port} ssl;
            listen [::]:${toString cfg.port} ssl;
            ssl_certificate /var/lib/acme/${domain}/fullchain.pem;
            ssl_certificate_key /var/lib/acme/${domain}/key.pem;
            ssl_trusted_certificate /var/lib/acme/${domain}/full.pem;
            proxy_pass znc-irc;
          }
        '';
      };
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
