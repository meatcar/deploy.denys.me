{
  self,
  inputs,
  lib,
  ...
}:
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
          orb-access = import ../tests/orb-access/check.nix {
            inherit pkgs;
            src = self;
          };
          cli-proxy-isolation = import ../nixos/modules/quadlets/cli-proxy-api/isolation-test.nix {
            inherit pkgs;
          };
          niks3-policy = import ../nixos/modules/niks3/policy-test.nix {
            inherit pkgs;
            inherit (inputs) niks3;
          };
          application-routing = import ../nixos/modules/quadlets/routing-test.nix {
            inherit pkgs;
          };
          container-network-subnets =
            let
              networks =
                self.nixosConfigurations.chunkymonkey.config.home-manager.users.pod.virtualisation.quadlet.networks;
              subnets = lib.concatMap (network: network.networkConfig.subnets) (builtins.attrValues networks);
            in
            assert builtins.all (network: network.networkConfig.subnets != [ ]) (builtins.attrValues networks);
            assert builtins.length subnets == builtins.length (lib.unique subnets);
            pkgs.runCommand "container-network-subnets" { } "touch $out";
          private-access-isolation = import ../nixos/modules/private-access/isolation-test.nix {
            inherit pkgs;
          };
          znc-loopback = pkgs.runCommand "znc-loopback" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            export PYTHONDONTWRITEBYTECODE=1
            python -m unittest discover -s ${../nixos/modules/znc} -p 'test_*.py'
            touch "$out"
          '';
          znc-mutable-upgrade = import ../nixos/modules/znc/upgrade-test.nix {
            inherit pkgs;
          };
          vpn-coexistence =
            let
              hosts = map (name: self.nixosConfigurations.${name}.config) [
                "chunkymonkey"
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
            pkgs.runCommand "vpn-coexistence" { } "touch $out";
          vps-private-http =
            let
              vps = self.nixosConfigurations.vps.config;
              privateListener =
                vhost:
                lib.any (listener: listener.port == 9443 && listener.ssl) vhost.listen
                && lib.all (listener: listener.port == 80 || listener.port == 9443) vhost.listen;
            in
            assert privateListener vps.services.nginx.virtualHosts."znc.denys.me";
            assert !(vps.virtualisation.oci-containers.containers ? mumbledj);
            assert vps.services.murmur.enable;
            pkgs.runCommand "vps-private-http" { } "touch $out";
          vps-private-services =
            let
              vps = self.nixosConfigurations.vps.config;
            in
            assert !vps.services.openssh.openFirewall;
            assert !vps.programs.mosh.openFirewall;
            assert !(builtins.elem 22 vps.networking.firewall.allowedTCPPorts);
            assert builtins.elem 22 vps.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
            assert builtins.elem 9443 vps.networking.firewall.interfaces.wt0.allowedTCPPorts;
            assert !(builtins.elem 7000 vps.networking.firewall.allowedTCPPorts);
            assert vps.services.znc.config.Listener.l.Host == "127.0.0.1";
            assert
              lib.sort builtins.lessThan (lib.unique vps.networking.firewall.allowedTCPPorts) == [
                80
                443
                64738
              ];
            pkgs.runCommand "vps-private-services" { } "touch $out";
          bao-sync = config.packages.bao-sync;
          cli-proxy-api = config.packages.cli-proxy-api-ops;
          deps = config.packages.deps;
          deps-lint = pkgs.runCommand "deps-lint" { nativeBuildInputs = [ config.packages.deps ]; } ''
            cd ${self}
            find . -type f -printf '%P\n' | xargs deps lint
            touch "$out"
          '';
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
