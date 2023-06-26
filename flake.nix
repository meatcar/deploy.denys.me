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
              IP=$(cd terraform && ${pkgs.terraform}/bin/terraform output --raw ip)
              REMOTE_USER=meatcar
              REMOTE_HOST=$REMOTE_USER@$IP
              nixos-rebuild "$@" \
                --flake .#vps \
                --target-host "$REMOTE_HOST" \
                --use-remote-sudo \
                --build-host "$REMOTE_HOST" \
                --use-substitutes
            '')
          ];
        in
        {
          devShells.default = pkgs.mkShell rec {
            name = "deploy.denys.me";
            BASE_NIX_VERSION = self.nixosConfigurations.image.config.system.stateVersion;
            buildInputs = scripts ++ (with pkgs; [
              inputs.agenix.defaultPackage.${system}

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
            inputs.agenix.nixosModules.age
            {
              age.secrets = {
                wg-priv-key.file = ./secrets/wg-priv-key.age;
                restic-password.file = ./secrets/restic-password.age;
                restic-env.file = ./secrets/restic-env.age;
              };
            }
            ./nixos/systems/vps.nix
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
      };
    };
}
