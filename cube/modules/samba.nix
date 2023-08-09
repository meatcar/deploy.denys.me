{ config, pkgs, inputs, ... }:
{
  services.samba = {
    enable = true;
    extraConfig = ''
      workgroup = WORKGROUP
      guest account = ${config.storageUser}
      map to guest = Bad Password
      server min protocol = SMB2_10
      client min protocol = SMB2
      client max protocol = SMB3
    '';
    shares = {
      data = {
        browseable = "yes";
        "guest ok" = "yes";
        path = "/data";
        public = "yes";
        writeable = "yes";
      };
    };
  };

  systemd.services.samba-wsdd =
    let
      wsdd = inputs.wsdd;
    in
    {
      enable = true;
      description = "Web Service Discovery Daemon";
      documentation = [ "https://github.com/christgau/wsdd" ];
      after = [
        "network-online.target"
        "samba-smbd.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${wsdd}/src/wsdd.py --shortlog";
        User = config.storageUser;
        Group = config.storageGroup;
      };
    };

  networking.firewall.allowedTCPPorts = [ 445 139 ] ++ [ 3702 5357 ];
  networking.firewall.allowedUDPPorts = [ 137 138 ];
}
