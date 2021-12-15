{
  description = "changeme";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, ... }@inputs:
    (inputs.flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          sops = pkgs.callPackage inputs.sops-nix { };
          nix = pkgs.nixFlakes;
        in
        {
          devShell = pkgs.mkShell rec {
            name = "cube-denys-me";
            buildInputs = [
              sops.ssh-to-pgp
              nix
              (pkgs.nixos-rebuild.override { inherit nix; })
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
    };
}
