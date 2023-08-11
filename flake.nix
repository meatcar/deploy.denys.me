{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:nixos/nixos-hardware";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
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
  };

  outputs = { self, ... }@inputs:
    let
      nixpkgsConfig = { config = { allowUnfree = true; }; };
      specialArgs = { inherit inputs; };
    in
    inputs.flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import inputs.nixpkgs (nixpkgsConfig // { inherit system; });
          scripts = [
            (pkgs.writeShellScriptBin "deploy" ''
              FLAKE="$1"; shift 1
              REMOTE_HOST=
              case "$FLAKE" in
                vps)
                  REMOTE_HOST=$(cd terraform && ${pkgs.terraform}/bin/terraform output --raw ip)
                  ;;
                cube)
                  REMOTE_HOST=10.100.0.4
                  ;;
                *)
                  echo no such remote host "$FLAKE" >&2
                  exit 1
              esac

              if ! ${pkgs.iputils}/bin/ping -c1 -W1 "$REMOTE_HOST"; then
                echo "$0: no connection to $REMOTE_HOST" >&2
                exit 1
              fi

              cmd=$(echo nixos-rebuild "$@" \
                --flake .#"$FLAKE" \
                --target-host "$REMOTE_HOST" \
                --build-host "$REMOTE_HOST" \
                --use-remote-sudo \
                --use-substitutes)
              echo "$cmd"
              $cmd
            '')
          ];
        in
        {
          devShells.default = pkgs.mkShell rec {
            name = "deploy.denys.me";
            BASE_NIX_VERSION = self.nixosConfigurations.image.config.system.stateVersion;
            buildInputs = scripts ++ (with pkgs; [
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
              awscli
              wireguard-tools
              jq
              flyctl

              packer
              nixos-generators
            ]);
          };
        }) // {
      nixosConfigurations = {
        image = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            ./nixos/modules/base.nix
            ./nixos/modules/digitalocean.nix
            {
              system.stateVersion = "22.11";
              mine.githubKeyUser = "meatcar";
              mine.username = "meatcar";
            }
          ];
        };
        vps = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "x86_64-linux";
          modules = [
            {
              nixpkgs = nixpkgsConfig;
              system.stateVersion = "22.05";
            }
            inputs.agenix.nixosModules.default
            {
              age.secrets = {
                wg-priv-key.file = ./secrets/wg-priv-key.age;
                restic-password.file = ./secrets/restic-password.age;
                restic-env.file = ./secrets/restic-env.age;
                restic-repo.file = ./secrets/restic-repo.age;
              };
            }
            ./nixos/systems/vps/vps.nix
          ];
        };
        rpi = inputs.nixpkgs.lib.nixosSystem {
          inherit specialArgs;
          system = "aarch64-linux";
          modules = [
            {
              nixpkgs = nixpkgsConfig;
              system.stateVersion = "22.05";
            }
            inputs.nixos-hardware.nixosModules.raspberry-pi-4
            ./nixos/systems/rpi.nix
          ];
        };
        cube = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs =
            { inherit inputs; };
          modules = [
            inputs.agenix.nixosModules.default
            ./cube/secrets/module.nix # agenix encrypted sensitive secrets
            ./cube/modules/unencrypted-secrets.nix # less sensitive secrets that shouldn't be in git history
            ./cube/configuration.nix
          ];
        };
      };
    };
}
