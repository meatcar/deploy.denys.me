{ config, pkgs, ... }:
let
  image = "ghcr.io/silverbulletmd/silverbullet:2.12.1-slim@sha256:7e24c16d31a3f4b4a4832ed64ec585e605a1e275b7c35917d385176f0b40415c";
  dataDir = "${config.mine.persistPath}/silverbullet";
  quadlet = config.home-manager.users.pod.virtualisation.quadlet;
  routes = pkgs.writeText "silverbullet-routes.yml" (
    builtins.toJSON (
      import ./routes.nix {
        publicHost = "txt.pvlv.ca";
        adminHost = "txt.vpn.denys.me";
      }
    )
  );
  backup = pkgs.writeShellApplication {
    name = "silverbullet-backup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnutar
      pkgs.systemd
    ];
    text = builtins.readFile ./backup.sh;
  };
in
{
  systemd.tmpfiles.rules = [ "d ${dataDir} 0700 pod pod - -" ];

  home-manager.users.pod.systemd.user.services.silverbullet-backup = {
    Unit.Description = "Archive SilverBullet data at rest";
    Service = {
      Type = "oneshot";
      ExecStart = "${backup}/bin/silverbullet-backup ${dataDir} ${config.mine.persistPath}/dumps/silverbullet.tar";
      TimeoutStartSec = "15min";
      UMask = "0077";
    };
  };

  home-manager.users.pod.virtualisation.quadlet = {
    networks.silverbullet.networkConfig = {
      name = "silverbullet";
      subnets = [ "10.89.5.0/24" ];
    };
    containers.traefik.containerConfig = {
      networks = [ quadlet.networks.silverbullet.ref ];
      volumes = [ "${routes}:/etc/traefik/dynamic/silverbullet.yml:ro" ];
    };
    containers.silverbullet = {
      autoStart = true;
      containerConfig = {
        inherit image;
        name = "silverbullet";
        networks = [ quadlet.networks.silverbullet.ref ];
        volumes = [ "${dataDir}:/data" ];
        environments = {
          # Container root is the rootless pod user; skip the entrypoint's su.
          PUID = "0";
          PGID = "0";
        };
        dropCapabilities = [ "all" ];
        noNewPrivileges = true;
        readOnly = true;
        tmpfses = [ "/tmp" ];
      };
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 5;
        MemoryHigh = "512M";
        MemoryMax = "1G";
      };
    };
  };
}
