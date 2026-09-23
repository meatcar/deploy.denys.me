{ self, lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks =
        lib.optionalAttrs pkgs.stdenv.isLinux (
          import ../terraform/checks.nix {
            inherit pkgs;
            src = self;
          }
        )
        // lib.optionalAttrs pkgs.stdenv.isLinux {
          cli-proxy-isolation = import ../nixos/modules/quadlets/cli-proxy-api/isolation-test.nix {
            inherit pkgs;
          };
          vpn-coexistence =
            let
              hosts = map (name: self.nixosConfigurations.${name}.config) [
                "chunkymonkey"
                "cube"
                "vps"
              ];
            in
            assert builtins.all (
              host:
              let
                netbird = host.services.netbird.clients.default;
              in
              host.services.tailscale.enable
              && netbird.port == 51822
              && netbird.interface == "wt0"
              && !netbird.openInternalFirewall
              && netbird.config.DisableDNS
              && netbird.config.DisableClientRoutes
              && netbird.config.DisableServerRoutes
              && !netbird.config.ServerSSHAllowed
            ) hosts;
            assert self.nixosConfigurations.chunkymonkey.config.virtualisation.docker.enable;
            assert
              self.nixosConfigurations.chunkymonkey.config.networking.firewall.interfaces.tailscale0.allowedTCPPorts
              == [ 22 ];
            assert !(self.nixosConfigurations.vps.config.age.secrets ? wg-priv-key);
            assert !((import ../secrets/secrets.nix) ? "wg-server-priv-key.age");
            pkgs.runCommand "vpn-coexistence" { } "touch $out";
          cube-vpn =
            let
              cube = self.nixosConfigurations.cube.config;
              containers = cube.virtualisation.oci-containers.containers;
              inherit (containers) gluetun;
              service = cube.systemd.services.docker-gluetun;
              secret = cube.age.secrets.wgConfig;
            in
            assert !(containers ? wireguard);
            assert secret.file == ../secrets/wg-config.age;
            assert secret.path == "/run/agenix/wgConfig";
            assert secret.mode == "0400";
            assert secret.owner == "root" && secret.group == "root";
            assert service.restartTriggers == [ ../secrets/wg-config.age ];
            assert !(cube.systemd.paths ? wgConfig-watcher);
            assert
              (import ../secrets/secrets.nix)."wg-config.age".publicKeys == [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH7aKNMDTXhMoruZYYAqbGY2XBY4Uy81zXHYxs7w6UoR"
              ];
            assert gluetun.environment.VPN_SERVICE_PROVIDER == "custom";
            assert gluetun.environment.VPN_TYPE == "wireguard";
            assert gluetun.environment.WIREGUARD_IMPLEMENTATION == "userspace";
            assert gluetun.environment.FIREWALL_INPUT_PORTS == "9091,9117";
            assert
              lib.sort builtins.lessThan gluetun.ports == [
                "127.0.0.1:9091:9091"
                "127.0.0.1:9117:9117"
              ];
            assert !gluetun.privileged;
            assert gluetun.capabilities == { NET_ADMIN = true; };
            assert gluetun.devices == [ "/dev/net/tun:/dev/net/tun" ];
            assert builtins.elem
              "--mount=type=bind,src=/run/agenix/wgConfig,dst=/gluetun/wireguard/wg0.conf,readonly"
              gluetun.extraOptions;
            assert builtins.all
              (
                name:
                containers.${name}.dependsOn == [ "gluetun" ]
                && containers.${name}.networks == [ "container:gluetun" ]
                && containers.${name}.ports == [ ]
                && containers.${name}.extraOptions == [ ]
              )
              [
                "transmission"
                "jackett"
              ];
            assert service.unitConfig.AssertPathExists == "/run/agenix/wgConfig";
            assert service.serviceConfig.TimeoutStartSec == 180;
            assert service.serviceConfig.Restart == "always";
            assert service.postStart != "";
            assert builtins.all
              (
                name:
                let
                  app = cube.systemd.services."docker-${name}";
                in
                builtins.elem "docker-gluetun.service" app.after
                && builtins.elem "docker-gluetun.service" app.requires
                && builtins.elem "docker-gluetun.service" app.bindsTo
                && builtins.elem "docker-gluetun.service" app.partOf
                && builtins.elem "docker-${name}.service" service.wants
              )
              [
                "transmission"
                "jackett"
              ];
            pkgs.runCommand "cube-vpn" { } "touch $out";
          cli-proxy-api = config.packages.cli-proxy-api-ops;
          bao-operations =
            pkgs.runCommand "bao-operations"
              {
                nativeBuildInputs = [ pkgs.python3 ];
              }
              ''
                export PYTHONDONTWRITEBYTECODE=1
                python -m unittest discover -s ${../nixos/systems/vpn} -p 'test_*.py'
                touch "$out"
              '';
          vpn-isolation = import ../nixos/systems/vpn/isolation-test.nix { inherit pkgs; };
          bao-vps =
            let
              bao = self.nixosConfigurations.baoVps.config;
            in
            assert bao.boot.loader.grub.devices == [ "/dev/sda" ];
            assert bao.disko.devices.disk.system.device == "/dev/sda";
            assert !bao.systemd.services.openstack-init.enable;
            assert !bao.systemd.services.apply-ec2-data.enable;
            assert !bao.virtualisation.amazon-init.enable;
            assert bao.services.netbird.clients.default.config.ManagementURL.Host == "api.netbird.io:443";
            assert bao.networking.firewall.allowedTCPPorts == [ 22 ];
            assert bao.networking.firewall.interfaces.wt0.allowedTCPPorts == [ 443 ];
            assert bao.services.openbao.settings.listener.private.address == "10.201.219.143:443";
            assert bao.services.openbao.settings.api_addr == "https://bao.vpn.denys.me";
            assert bao.systemd.services.openbao.serviceConfig.AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ];
            assert !bao.systemd.services.openbao.serviceConfig.PrivateUsers;
            assert builtins.elem "AF_NETLINK"
              bao.systemd.services.openbao.serviceConfig.RestrictAddressFamilies;
            assert
              bao.users.users.root.openssh.authorizedKeys.keys == [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBcq01gh2tn/+hcm75N3LnS003mUBjXcT6qNndMhObPO me@onepassword"
              ];
            pkgs.runCommand "bao-vps" { } "touch $out";
          vpn-host-separation =
            let
              vpn = self.nixosConfigurations.vpn.config;
              bao = self.nixosConfigurations.bao.config;
            in
            assert !vpn.services.openbao.enable;
            assert !vpn.services.netbird.enable;
            assert vpn.services.traefik.enable;
            assert bao.services.openbao.enable;
            assert bao.services.netbird.enable;
            assert !bao.services.traefik.enable;
            assert bao.virtualisation.oci-containers.containers == { };
            assert bao.networking.firewall.allowedTCPPorts == [ 22 ];
            assert bao.networking.firewall.interfaces.wt0.allowedTCPPorts == [ 443 ];
            assert !(builtins.elem "/var/lib/openbao/audit.log" vpn.services.restic.backups.vpn.paths);
            pkgs.runCommand "vpn-host-separation" { } "touch $out";
        };
    };
}
