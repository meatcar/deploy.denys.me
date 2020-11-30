{ pkgs ? import <nixpkgs> { } }:
let
  sources = import ./nix/sources.nix;
  sops = pkgs.callPackage sources.sops-nix { };
in
pkgs.mkShell {
  name = "cube-denys-me";
  buildInputs = [ pkgs.niv sops.ssh-to-pgp ];
  nativeBuildInputs = [ sops.sops-pgp-hook ];
  sopsPGPKeyDirs = [
    "./keys/hosts"
    "./keys/users"
  ];
}
