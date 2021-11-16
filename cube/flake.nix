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
        in
        {
          devShell = pkgs.mkShell rec {
            name = "cube-denys-me";
            buildInputs = [ sops.ssh-to-pgp ];
            nativeBuildInputs = [ sops.sops-pgp-hook ];
            sopsPGPKeyDirs = [
              "./keys/hosts"
              "./keys/users"
            ];
          };
        }));
}
