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
            pkgs.runCommand "vpn-coexistence" { } "touch $out";
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
