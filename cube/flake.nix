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
          deploy = pkgs.writeScriptBin "deploy" ''
            nixos-rebuild "$@" \
              --flake .#cube \
              --target-host 10.100.0.4 --build-host 10.100.0.4 \
              --use-substitutes --use-remote-sudo
          '';
        in
        {
          devShells.default = pkgs.mkShell rec {
            name = "cube-denys-me";
            buildInputs = with pkgs; [
              nixFlakes
              (pkgs.nixos-rebuild.override { nix = nixFlakes; })
              inputs.agenix.packages.${system}.default
              deploy
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
          inputs.agenix.nixosModules.default
          ./secrets/module.nix # agenix encrypted sensitive secrets
          ./modules/unencrypted-secrets.nix # less sensitive secrets that shouldn't be in git history
          ./configuration.nix
        ];
      };
    };
}
