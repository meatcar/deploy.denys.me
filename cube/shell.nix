{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "env";
  buildInputs = [];
}

