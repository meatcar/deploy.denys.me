{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/25.05";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    wsdd = {
      url = "github:christgau/wsdd";
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
    in
    inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import inputs.nixpkgs (nixpkgs // { inherit system; });
        scripts = [
          (pkgs.writeShellScriptBin "deploy" ''
            FLAKE="$1"; shift 1
            REMOTE_HOST=
            REMOTE_OPTS= # opts to pass to nixos-rebuild
            BUILD_HOST=
            case "$FLAKE" in
              chunkymonkey)
                REMOTE_HOST=chunkymonkey.fish-hydra.ts.net
                BUILD_HOST="$REMOTE_HOST"
                ;;
              vps)
                REMOTE_HOST=$(cd terraform && ${pkgs.terraform}/bin/terraform output --raw ip)
                BUILD_HOST="$REMOTE_HOST"
                ;;
              # cube)
              #   REMOTE_HOST=cube.fish-hydra.ts.net
              #   REMOTE_OPTS=--impure
              #   BUILD_HOST="$REMOTE_HOST"
              #   ;;
              *)
                echo no such remote host "$FLAKE" >&2
                exit 1
            esac

            if ! ssh -o ConnectTimeout=5 "$REMOTE_HOST" exit; then
              echo "$0: no connection to $REMOTE_HOST" >&2
              exit 1
            fi

            cmd=$(echo nixos-rebuild "$@" \
              --flake .#"$FLAKE" \
              --target-host "$REMOTE_HOST" \
              --build-host "$BUILD_HOST" \
              --use-remote-sudo \
              --use-substitutes $REMOTE_OPTS)
            echo "$cmd"
            $cmd
          '')
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          name = "deploy.denys.me";
          BASE_NIX_VERSION = self.nixosConfigurations.doImage.config.system.stateVersion;
          buildInputs =
            # scripts ++
            (
              with pkgs;
              [
                nil
                nixd
                inputs.agenix.packages.${system}.default

                (terraform.withPlugins (p: [
                  p.local
                  p.external
                  p.null
                  p.random
                  p.aws
                  p.digitalocean
                  p.cloudflare
                ]))
                awscli2
                wireguard-tools
                jq
                flyctl
                oci-cli

                packer
                nixos-generators
                inputs.deploy-rs.packages.${system}.default
              ]
            );
        };
      }
    )
    // {
      nixosConfigurations = {
        doImage = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            ./nixos/modules/base.nix
            ./nixos/modules/digitalocean.nix
            {
              system.stateVersion = "25.05";
              mine.githubKeyUser = "meatcar";
              mine.username = "meatcar";
            }
          ];
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
      # FIXME: aarch check errors out on x86_64-linux and vice versa.
      # checks = builtins.mapAttrs (
      #   system: deployLib: deployLib.deployChecks self.deploy
      # ) inputs.deploy-rs.lib;
      checks = { };
    };
}
