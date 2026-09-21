{
  description = "changeme";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/26.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    age-plugin-1p.url = "github:Enzime/age-plugin-1p";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wsdd = {
      url = "github:christgau/wsdd";
      flake = false;
    };

    sshkeys = {
      url = "file+https://github.com/meatcar.keys";
      flake = false;
    };

    website = {
      url = "github:meatcar/denys.me";
      flake = false;
    };

    transit-dashboard.url = "git+ssh://git@github.com/meatcar/transit-dashboard";
  };

  outputs =
    { self, ... }@inputs:
    let
      nixpkgs = {
        config = {
          allowUnfree = true;
        };
      };
      specialArgs = { inherit inputs; };
      doImageModules = [
        ./nixos/modules/base.nix
        ./nixos/modules/digitalocean.nix
        {
          system.stateVersion = "25.05";
          mine.username = "meatcar";
        }
      ];
    in
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs (nixpkgs // { inherit system; });
        treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        cliProxyApi = import ./packages/cli-proxy-api/package.nix { inherit pkgs; };
      in
      {
        formatter = treefmtEval.config.build.wrapper;
        checks = {
          treefmt = treefmtEval.config.build.check self;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux (
          import ./terraform/checks.nix {
            inherit pkgs;
            src = self;
          }
        )
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          cli-proxy-isolation = import ./nixos/modules/quadlets/cli-proxy-api/isolation-test.nix {
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
          cli-proxy-api = cliProxyApi;
          vpn-isolation = import ./nixos/systems/vpn/isolation-test.nix { inherit pkgs; };
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
        packages =
          inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            cli-proxy-api-ops = cliProxyApi;
          }
          // inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
            doImage = self.nixosConfigurations.doImage.config.system.build.image;
            baoImage = self.nixosConfigurations.bao.config.system.build.images.openstack;
            baoInstaller = pkgs.nixos-anywhere.overrideAttrs (old: {
              # NOTE: Upstream disables host verification before applying CLI SSH options.
              # see https://github.com/nix-community/nixos-anywhere/issues/552
              postPatch = (old.postPatch or "") + ''
                substituteInPlace src/nixos-anywhere.sh \
                  --replace-fail 'UserKnownHostsFile=/dev/null' 'UserKnownHostsFile=''${NIXOS_ANYWHERE_KNOWN_HOSTS:-$HOME/.ssh/known_hosts}' \
                  --replace-fail 'StrictHostKeyChecking=no' 'StrictHostKeyChecking=yes'
              '';
            });
          };

        devShells.default = pkgs.mkShell {
          name = "deploy.denys.me";
          # NOTE: Watson's home cache is on a noexec filesystem.
          shellHook = ''
            export TG_PROVIDER_CACHE_DIR="''${TG_PROVIDER_CACHE_DIR:-$PWD/.terragrunt-cache/providers}"
          '';
          CLI_PROXY_API_CONFIG = toString ./nixos/systems/chunkymonkey/cli-proxy-api.json;
          CLI_PROXY_API_TEST_SETTINGS = builtins.toJSON (
            import ./nixos/modules/quadlets/cli-proxy-api/settings.nix {
              publicHost = "api.example.test";
              bridgeVersion =
                (import ./nixos/modules/quadlets/cli-proxy-api/images.nix { inherit pkgs; }).bridge.version;
            }
          );
          buildInputs = [
            cliProxyApi
          ]
          ++ (with pkgs; [
            nil
            nixd
            inputs.agenix.packages.${system}.default
            inputs.age-plugin-1p.packages.${system}.age
            inputs.age-plugin-1p.packages.${system}.age-plugin-1p

            awscli2
            openbao
            wireguard-tools
            jq
            flyctl
            railway
            oci-cli
            opentofu
            terragrunt
            tflint
            python3
            python3Packages.pytest
            ruff
            python3Packages.python-openstackclient
            shellcheck

            deploy-rs
          ]);
        };
      }
    )
    // {
      nixosConfigurations = {
        vpn = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nixos/systems/vpn/configuration.nix ];
        };
        bao = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./nixos/systems/bao/configuration.nix ];
        };
        baoVps = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            ./nixos/systems/bao/vps.nix
          ];
        };
        doImage = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = doImageModules;
        };
        chunkymonkey = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "aarch64-linux";
          modules = [
            {
              inherit nixpkgs;
              system.stateVersion = "23.11";
            }
            inputs.agenix.nixosModules.default
            inputs.home-manager.nixosModules.home-manager
            ./nixos/systems/chunkymonkey/configuration.nix
          ];
        };
        vps = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            {
              inherit nixpkgs;
              system.stateVersion = "25.05";
            }
            inputs.agenix.nixosModules.default
            ./nixos/systems/vps/configuration.nix
          ];
        };
        cube = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            {
              inherit nixpkgs;
              system.stateVersion = "25.05";
            }
            inputs.agenix.nixosModules.default
            ./nixos/systems/cube/configuration.nix
          ];
        };
      };
    }
    // {
      deploy = {
        sshUser = "meatcar";
        user = "root";
        remoteBuild = true;
        fastConnection = true;

        nodes = {
          bao = {
            hostname = "51.222.84.199";
            sshUser = "root";
            sshOpts = [
              "-o"
              "StrictHostKeyChecking=yes"
              "-o"
              "IdentityAgent=~/.1password/agent.sock"
              "-o"
              "UserKnownHostsFile=output/ovh-bao-vps/bao-known_hosts"
            ];
            profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.baoVps;
            remoteBuild = false;
          };
          chunkymonkey = {
            hostname = "chunkymonkey.fish-hydra.ts.net";
            profiles.system.path = inputs.deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.chunkymonkey;
          };
          vps = {
            hostname = "to.fish-hydra.ts.net";
            profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.vps;
            remoteBuild = false;
          };
          cube = {
            hostname = "cube.fish-hydra.ts.net";
            profiles.system.path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.cube;
          };
        };
      };
    };
}
