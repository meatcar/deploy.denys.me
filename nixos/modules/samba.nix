{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  lan = config.mine.privateAccess.trustedLANInterfaces;
in
{
  imports = [ ./private-access ];
  services.samba = {
    enable = true;
    smbd.enable = true;
    nmbd.enable = false;
    openFirewall = false;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "map to guest" = "Never";
        "restrict anonymous" = 2;
        "interfaces" = lib.concatStringsSep " " (
          [
            "lo"
            "wt0"
          ]
          ++ lan
        );
        "bind interfaces only" = "yes";
        "smb ports" = "445";
        "server min protocol" = "SMB2_10";
        "client min protocol" = "SMB2";
        "client max protocol" = "SMB3";
      };
      data = {
        browseable = "yes";
        "guest ok" = "no";
        "valid users" = "@${config.mine.storageGroup}";
        path = "/data";
        public = "no";
        writeable = "yes";
      };
    };
  };

  systemd.services.samba-wsdd =
    let
      inherit (inputs) wsdd;
    in
    {
      enable = lan != [ ];
      description = "Web Service Discovery Daemon";
      documentation = [ "https://github.com/christgau/wsdd" ];
      after = [
        "network-online.target"
        "samba-smbd.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${wsdd}/src/wsdd.py --shortlog ${
          lib.concatMapStringsSep " " (interface: "--interface ${interface}") lan
        }";
        User = config.mine.storageUser;
        Group = config.mine.storageGroup;
      };
    };

  networking.firewall.interfaces =
    lib.genAttrs lan (_: {
      allowedTCPPorts = [
        445
        5357
      ];
      allowedUDPPorts = [ 3702 ];
    })
    // {
      wt0.allowedTCPPorts = [ 445 ];
    };
}
