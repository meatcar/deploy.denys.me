{
  config,
  lib,
  ...
}:
let
  secret = config.age.secrets.wgConfig;
in
{
  age.secrets.wgConfig = {
    file = ../../../../../secrets/wg-config.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };

  assertions = [
    {
      assertion = builtins.pathExists secret.file;
      message = "Import secrets/wg-config.age with agenix before deploying Cube; see nixos/systems/cube/README.md.";
    }
  ];

  virtualisation.oci-containers.containers.gluetun = {
    image = "qmcgaw/gluetun:v3.41.3@sha256:fa19cc76b2af13d57a8d3dc3066f2ada061b1c761b8aecf989b3877c0486e027";
    capabilities.NET_ADMIN = true;
    devices = [ "/dev/net/tun:/dev/net/tun" ];
    environment = {
      VPN_SERVICE_PROVIDER = "custom";
      VPN_TYPE = "wireguard";
      WIREGUARD_IMPLEMENTATION = "userspace";
      FIREWALL_INPUT_PORTS = "9091,9117";
    };
    extraOptions = [
      "--mount=type=bind,src=${secret.path},dst=/gluetun/wireguard/wg0.conf,readonly"
    ];
  };

  systemd.services = {
    docker-gluetun = {
      unitConfig.AssertPathExists = secret.path;
      restartTriggers = [ secret.file ];
      wants = [
        "docker-transmission.service"
        "docker-jackett.service"
      ];
      postStart = builtins.readFile ./wait-healthy.sh;
      serviceConfig = {
        TimeoutStartSec = lib.mkForce 180;
        Restart = lib.mkForce "always";
        RestartSec = 10;
      };
    };
  }
  // lib.genAttrs [ "docker-transmission" "docker-jackett" ] (_: {
    bindsTo = [ "docker-gluetun.service" ];
    partOf = [ "docker-gluetun.service" ];
  });
}
