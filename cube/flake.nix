{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

  };
  outputs = { self, ... }@inputs:
    (inputs.flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            overlays = [ inputs.deploy-rs.overlay ];
          };
          sops = pkgs.callPackage inputs.sops-nix { };
        in
        {
          devShell = pkgs.mkShell rec {
            name = "cube-denys-me";
            buildInputs = [
              sops.ssh-to-pgp
              pkgs.nixFlakes
              (pkgs.nixos-rebuild.override { nix = pkgs.nixFlakes; })
              pkgs.deploy-rs.deploy-rs
            ];
            nativeBuildInputs = [
              sops.sops-import-keys-hook
            ];
            sopsPGPKeyDirs = [
              "./keys/hosts"
              "./keys/users"
            ];
          };
        }))
    // {
      nixosConfigurations.cube = inputs.nixpkgs.lib.nixosSystem {
        # customize to your system
        system = "x86_64-linux";
        specialArgs =
          { inherit inputs; };
        modules = [
          ./configuration.nix
          inputs.sops-nix.nixosModules.sops
        ];
      };
      deploy.nodes.cube = {
        hostname = "192.168.11.117";
        profiles.system = {
          user = "root";
          path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.cube;
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) inputs.deploy-rs.lib;
    };
}
