{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    wsdd = {
      url = "github:christgau/wsdd";
      flake = false;
    };

    plex-subzero = {
      url = "github:pannal/Sub-Zero.bundle";
      flake = false;
    };
  };
  outputs = { self, ... }@inputs:
    (inputs.flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          nix = pkgs.nixFlakes;
        in
        {
          devShell = pkgs.mkShell rec {
            name = "cube-denys-me";
            buildInputs = [
              nix
              (pkgs.nixos-rebuild.override { inherit nix; })
              inputs.agenix.defaultPackage.${system}
            ];
            shellHook = ''
              export NIX_SSHOPTS=-t
            '';
          };
        }))
    // {
      nixosConfigurations.cube = inputs.nixpkgs.lib.nixosSystem {
        # customize to your system
        system = "x86_64-linux";
        specialArgs =
          { inherit inputs; };
        modules = [
          inputs.agenix.nixosModules.age
          ./secrets/module.nix
          ./configuration.nix
        ];
      };
    };
}
