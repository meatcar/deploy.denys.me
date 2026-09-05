{ pkgs }:
let
  archive = pkgs.fetchurl {
    url = "https://github.com/openbao/openbao-plugins/releases/download/auth-aws-v0.1.1/openbao-plugin-auth-aws_linux_amd64_v1.tar.gz";
    sha256 = "e7ebbbe7ecdc7d19594b807b2eb6cfb3fe8012132b671a87cecc7a65c65512a3";
  };
in
assert pkgs.stdenv.hostPlatform.system == "x86_64-linux";
pkgs.runCommand "openbao-auth-aws-0.1.1" { } ''
  tar -xzf ${archive}
  install -Dm555 openbao-plugin-auth-aws_linux_amd64_v1 $out/openbao-plugin-auth-aws
''
