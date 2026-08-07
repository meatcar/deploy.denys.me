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
        scripts = [
          (pkgs.writeShellScriptBin "terraform" ''
            exec ${pkgs.opentofu}/bin/tofu "$@"
          '')
          (pkgs.writeShellScriptBin "deploy-sh" ''
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
                REMOTE_HOST=$(cd terraform && terraform output --raw ip)
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
        formatter = treefmtEval.config.build.wrapper;
        checks.treefmt = treefmtEval.config.build.check self;
        packages = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          doImage = self.nixosConfigurations.doImage.config.system.build.image;
        };

        devShells.default = pkgs.mkShell {
          name = "deploy.denys.me";
          buildInputs =
            scripts
            ++ (with pkgs; [
              nil
              nixd
              inputs.agenix.packages.${system}.default
              inputs.age-plugin-1p.packages.${system}.age
              inputs.age-plugin-1p.packages.${system}.age-plugin-1p
              _1password-cli

              awscli2
              wireguard-tools
              jq
              flyctl
              railway
              oci-cli
              tflint

              deploy-rs
            ]);
        };
      }
    )
    // {
      nixosConfigurations = {
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
