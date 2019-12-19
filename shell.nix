{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  buildInputs = [
    pkgs.terraform-full
    pkgs.packer
    (pkgs.callPackage (fetchGit https://github.com/nix-community/nixos-generators) {})
    pkgs.wireguard
    pkgs.jq
  ];
}
